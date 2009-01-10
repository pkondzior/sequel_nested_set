unless Object.respond_to?(:returning)
  class Object
    def returning(value)
      yield(value)
      value
    end
  end
end

module Sequel
  module Plugins
    # This acts provides Nested Set functionality. Nested Set is a smart way to implement
    # an _ordered_ tree, with the added feature that you can select the children and all of their
    # descendants with a single query. The drawback is that insertion or move need some complex
    # sql queries. But everything is done here by this module!
    #
    # Nested sets are appropriate each time you want either an orderd tree (menus,
    # commercial categories) or an efficient way of querying big trees (threaded posts).
    #
    # == API
    #
    #   # adds a new item at the "end" of the tree, i.e. with child.left = max(tree.right)+1
    #   child = MyClass.new(:name => "child1")
    #   child.save
    #   # now move the item to its right place
    #   child.move_to_child_of my_item
    #
    # You can pass an id or an object to:
    # * <tt>#move_to_child_of</tt>
    # * <tt>#move_to_right_of</tt>
    # * <tt>#move_to_left_of</tt>
    #
    module NestedSet
      # Configuration options are:
      #
      # * +:parent_column+ - specifies the column name to use for keeping the position integer (default: :parent_id)
      # * +:left_column+ - column name for left boundry data, default :lft
      # * +:right_column+ - column name for right boundry data, default :rgt
      # * +:scope+ - restricts what is to be considered a list. Given a symbol, it'll attach "_id"
      #   (if it hasn't been already) and use that as the foreign key restriction. You
      #   can also pass an array to scope by multiple attributes.
      #   Example: <tt>is :nested_set, { :scope => [:notable_id, :notable_type] }</tt>
      # * +:dependent+ - behavior for cascading destroy. If set to :destroy, all the
      #   child objects are destroyed alongside this object by calling their destroy
      #   method. If set to :delete_all (default), all the child objects are deleted
      #   without calling their destroy method.
      #
      # See Sequle::Plugins::NestedSet::ClassMethods for a list of class methods and
      # Sequle::Plugins::NestedSet::InstanceMethods for a list of instance methods added
      # to acts_as_nested_set models
      def self.apply(model, options = {})
        options = {
          :parent_column => :parent_id,
          :left_column => :lft,
          :right_column => :rgt,
          :dependent => :delete_all, # or :destroy
        }.merge(options)

        if options[:scope].is_a?(Symbol) && options[:scope].to_s !~ /_id$/
          options[:scope] = "#{options[:scope]}_id".to_sym
        end
        
        model.class.class_eval do
          attr_accessor :nested_set_options
        end
        model.nested_set_options = options

        model.before_create { set_default_left_and_right }
        model.before_destroy { prune_from_tree }

        model.set_restricted_columns(*([:left, :right, :parent_id, options[:parent_column], options[:left_column], options[:right_column]].uniq))
      end

      module DatasetMethods
        # All nested set queries should use this nested dataset method, which returns Dataset that provides
        # proper :scope which you can configure on is :nested, { :scope => ... }
        # declaration in your Sequel::Model
        def nested
          order(self.model_classes[nil].qualified_left_column)
        end

        # Returns dataset for all root nodes
        def roots
          nested.filter(self.model_classes[nil].qualified_parent_column => nil)
        end

        # Returns dataset for all of nodes which do not have children
        def leaves
          nested.filter(self.model_classes[nil].qualified_right_column - self.model_classes[nil].qualified_left_column => 1)
        end
      end

      module ClassMethods

        # Returns the first root
        def root
          roots.first
        end
        
        def qualified_parent_column(table_name = self.implicit_table_name)
          "#{table_name}__#{self.nested_set_options[:parent_column]}".to_sym
        end

        def qualified_parent_column_literal
          self.dataset.literal(self.nested_set_options[:parent_column])
        end

        def qualified_left_column(table_name = self.implicit_table_name)
          "#{table_name}__#{self.nested_set_options[:left_column]}".to_sym
        end

        def qualified_left_column_literal
          self.dataset.literal(self.nested_set_options[:left_column])
        end

        def qualified_right_column(table_name = self.implicit_table_name)
          "#{table_name}__#{self.nested_set_options[:right_column]}".to_sym
        end

        def qualified_right_column_literal
          self.dataset.literal(self.nested_set_options[:right_column])
        end

        def valid?
          self.left_and_rights_valid? && self.no_duplicates_for_columns? && self.all_roots_valid?
        end

        def left_and_rights_valid?
          self.left_outer_join(Client.implicit_table_name.as(:parent), self.qualified_parent_column => "parent__#{self.primary_key}".to_sym).
            filter({ self.qualified_left_column => nil } |
              { self.qualified_right_column => nil } |
              (self.qualified_left_column >= self.qualified_right_column) |
            (~{ self.qualified_parent_column => nil } & ((self.qualified_left_column <= self.qualified_left_column(:parent)) |
              (self.qualified_right_column >= self.qualified_right_column(:parent))))).count == 0
        end

        def left_and_rights_valid_dataset?
          self.left_outer_join(Client.implicit_table_name.as(:parent), self.qualified_parent_column => "parent__#{self.primary_key}".to_sym).
            filter({ self.qualified_left_column => nil } |
              { self.qualified_right_column => nil } |
              (self.qualified_left_column >= self.qualified_right_column) |
            (~{ self.qualified_parent_column => nil } & ((self.qualified_left_column <= self.qualified_left_column(:parent)) |
              (self.qualified_right_column >= self.qualified_right_column(:parent)))))
        end

        def no_duplicates_for_columns?
          # TODO: scope
          #          scope_columns = Array(self.nested_set_options[:scope]).map do |c|
          #            connection.quote_column_name(c)
          #          end.push(nil).join(", ")
          [self.qualified_left_column, self.qualified_right_column].all? do |column|
            self.dataset.select(column, :count[column]).group(column).having(:count[column] > 1).first.nil?
          end
        end

        # Wrapper for each_root_valid? that can deal with scope.
        def all_roots_valid?
          # TODO: scope
#          if self.nested_set_options[:scope]
#            roots.group(:group => scope_column_names).group_by{|record| scope_column_names.collect{|col| record.send(col.to_sym)}}.all? do |scope, grouped_roots|
#              each_root_valid?(grouped_roots)
#            end
#          else
            each_root_valid?(roots.all)
#          end
        end

        def each_root_valid?(roots_to_validate)
          left = right = 0
          roots_to_validate.all? do |root|
            returning(root.left > left && root.right > right) do
              left = root.left
              right = root.right
            end
          end
        end
        
        # Rebuilds the left & rights if unset or invalid.  Also very useful for converting from acts_as_tree.
        def rebuild!

          scope = lambda{}
          # TODO: add scope stuff
          
          # Don't rebuild a valid tree.
          return true if valid?
          indices = {}
          
          move_to_child_of_lambda = lambda do |parent_node|
            # Set left
            parent_node[nested_set_options[:left_column]] = indices[scope.call(parent_node)] += 1
            # Gather child noodes of parend_node and iterate by children
            parent_node.children.order(:id).all.each do |child_node|
              move_to_child_of_lambda.call(child_node)
            end
            # Set right
            parent_node[nested_set_options[:right_column]] = indices[scope.call(parent_node)] += 1
            parent_node.save
          end

          # Gatcher root nodes and iterate by them
          self.roots.all.each do |root_node|
            # setup index for this scope
            indices[scope.call(root_node)] ||= 0
            move_to_child_of_lambda.call(root_node)
          end
        end

        def to_text(&block)
          text = []
          self.roots.each do |root|
            text << root.to_text(&block)
          end
          text.join("\n")
        end

        # Returns the entire set as a nested array. If flat is true then a flat
        # array is returned instead. Specify mover to exclude any impossible
        # moves. Pass a block to perform an operation on each item. The block
        # arguments are |item, level|.
        def to_nested_a(flat = false, mover = nil, &block)
          descendants = self.nested.all
          array = []

          while not descendants.empty?
            items = descendants.shift.to_nested_a(flat, mover, descendants, 0, &block)
            array.send flat ? 'concat' : '<<', items
          end

          return array
        end
      end

      module InstanceMethods

        # Returns hash of Model nested set options
        def nested_set_options
          self.class.nested_set_options
        end

        # Setter of the left column
        def left=(value)
          self[self.nested_set_options[:left_column]] = value
        end

        # Setter of the right column
        def right=(value)
          self[self.nested_set_options[:right_column]] = value
        end

        # Getter of the left column
        def left
          self[self.nested_set_options[:left_column]] || 0
        end

        # Getter of the right column
        def right
          self[self.nested_set_options[:right_column]] || 0
        end

        # Setter of the parent column
        def parent_id=(value)
          self[self.nested_set_options[:parent_column]] = value
        end

        # Getter of parent column
        def parent_id
          self[self.nested_set_options[:parent_column]]
        end

        # Set left=, right= and parent_id= to be procted methods
        # this methods should be used only internally by nested set plugin
        protected :left=, :right=, :parent_id=

        # Returns the level of this object in the tree
        # root level is 0
        def level
          root? ? 0 : ancestors.count
        end

        # Returns true if this is a root node
        def root?
          parent_id.nil?
        end

        # Returns true if this is a leaf node
        def leaf?
          right - left == 1
        end

        # Returns true is this is a child node
        def child?
          !root?
        end

        # order by left column
        def <=>(x)
          left <=> x.left
        end

        # Returns root
        def root
          self_and_ancestors.first
        end

        # Returns the immediate parent
        def parent
          dataset.nested.filter(self.primary_key => self.parent_id).first if self.parent_id
        end

        # Returns the dataset for all parent nodes and self
        def self_and_ancestors
          dataset.filter((self.class.qualified_left_column <= left) & (self.class.qualified_right_column  >= right))
        end

        # Returns the dataset for all children of the parent, including self
        def self_and_siblings
          dataset.nested.filter(self.class.qualified_parent_column  => self.parent_id)
        end

        # Returns dataset for itself and all of its nested children
        def self_and_descendants
          dataset.nested.filter((self.class.qualified_left_column >= left) & (self.class.qualified_right_column <= right))
        end

        # Filter for dataset that will exclude self object
        def without_self(dataset)
          dataset.nested.filter(~{self.primary_key => self.id})
        end

        # Returns dataset for its immediate children
        def children
          dataset.nested.filter(self.class.qualified_parent_column => self.id)
        end

        # Returns dataset for all parents
        def ancestors
          without_self(self_and_ancestors)
        end

        # Returns dataset for all children of the parent, except self
        def siblings
          without_self(self_and_siblings)
        end

        # Returns dataset for all of its children and nested children
        def descendants
          without_self(self_and_descendants)
        end

        # Returns dataset for all of its nested children which do not have children
        def leaves
          descendants.filter(self.class.qualified_right_column - self.class.qualified_left_column => 1)
        end

        def is_descendant_of?(other)
          other.left < self.left && self.left < other.right && same_scope?(other)
        end

        def is_or_is_descendant_of?(other)
          other.left <= self.left && self.left < other.right && same_scope?(other)
        end

        def is_ancestor_of?(other)
          self.left < other.left && other.left < self.right && same_scope?(other)
        end

        def is_or_is_ancestor_of?(other)
          self.left <= other.left && other.left < self.right && same_scope?(other)
        end

        # Check if other model is in the same scope
        def same_scope?(other)
          Array(nil).all? do |attr|
            self.send(attr) == other.send(attr)
          end
        end

        # Find the first sibling to the left
        def left_sibling
          siblings.filter(self.class.qualified_left_column < left).order(self.class.qualified_left_column.desc).first
        end

        # Find the first sibling to the right
        def right_sibling
          siblings.filter(self.class.qualified_left_column > left).first
        end


        # Shorthand method for finding the left sibling and moving to the left of it.
        def move_left
          self.move_to_left_of(self.left_sibling)
        end

        # Shorthand method for finding the right sibling and moving to the right of it.
        def move_right
          self.move_to_right_of(self.right_sibling)
        end

        # Move the node to the left of another node (you can pass id only)
        def move_to_left_of(node)
          self.move_to(node, :left)
        end

        # Move the node to the left of another node (you can pass id only)
        def move_to_right_of(node)
          self.move_to(node, :right)
        end

        # Move the node to the child of another node (you can pass id only)
        def move_to_child_of(node)
          self.move_to(node, :child)
        end

        # Move the node to root nodes
        def move_to_root
          self.move_to(nil, :root)
        end

        # Check if node move is possible for specific target
        def move_possible?(target)
          self != target && # Can't target self
          same_scope?(target) && # can't be in different scopes
          # !(left..right).include?(target.left..target.right) # this needs tested more
          # detect impossible move
          !((left <= target.left && right >= target.left) or (left <= target.right && right >= target.right))
        end

        # You can pass block that will have
        def to_text
          self_and_descendants.map do |node|
            if block_given?
              inspect = yield(node)
            else
              inspect = node.class.inspect
            end
            "#{'*'*(node.level+1)} #{inspect} (#{node.parent_id.inspect}, #{node.left}, #{node.right})"
          end.join("\n")
        end

        # Returns self and its descendants as a nested array. If flat is true
        # then a flat array is returned instead. Specify mover to exclude any
        # impossible moves. Pass a block to perform an operation on each item.
        # The block arguments are |item, level|. The remaining arguments for
        # this method are for recursion and should not normally be given.
        def to_nested_a(flat = false, mover = nil, descendants = nil, level = self.level, &block)
          descendants ||= self.descendants.all
          array = [ block_given? ? yield(self, level) : self ]

          while not descendants.empty?
            break unless descendants.first.parent_id == self.id
            item = descendants.shift
            items = item.to_nested_a(flat, mover, descendants, level + 1, &block)
            array.send flat ? 'concat' : '<<', items if mover.nil? or mover.new? or mover.move_possible?(item)
          end

          return array
        end

        protected
        # on creation, set automatically lft and rgt to the end of the tree
        def set_default_left_and_right
          maxright = dataset.nested.max(self.class.qualified_right_column).to_i || 0
          # adds the new node to the right of all existing nodes
          self.left = maxright + 1
          self.right = maxright + 2
        end

        # Prunes a branch off of the tree, shifting all of the elements on the right
        # back to the left so the counts still work.
        def prune_from_tree
          return if self.right.nil? || self.left.nil?
          diff = self.right - self.left + 1

          #TODO: implemente :dependent option
          #          delete_method = acts_as_nested_set_options[:dependent] == :destroy ?
          #            :destroy_all : :delete_all

          #TODO: implement prune method
          #          self.class.base_class.transaction do
          #            nested_set_scope.send(delete_method,
          #              ["#{quoted_left_column_name} > ? AND #{quoted_right_column_name} < ?",
          #                left, right]
          #            )
          #            nested_set_scope.update_all(
          #              ["#{quoted_left_column_name} = (#{quoted_left_column_name} - ?)", diff],
          #              ["#{quoted_left_column_name} >= ?", right]
          #            )
          #            nested_set_scope.update_all(
          #              ["#{quoted_right_column_name} = (#{quoted_right_column_name} - ?)", diff],
          #              ["#{quoted_right_column_name} >= ?", right]
          #            )
          #          end
        end

        # reload left, right, and parent
        def reload_nested_set
          reload(:select => "#{quoted_left_column_name}, " +
              "#{quoted_right_column_name}, #{quoted_parent_column_name}")
        end

        def move_to(target, position)
          raise Error, "You cannot move a new node" if self.new?
#          #TODO: add callback
          db.transaction do
            unless position == :root || self.move_possible?(target)
              raise Error, "Impossible move, target node cannot be inside moved tree."
            end

            bound = case position
              when :child;  target.right
              when :left;   target.left
              when :right;  target.right + 1
              when :root;   1
              else raise Error, "Position should be :child, :left, :right or :root ('#{position}' received)."
            end

            if bound > self.right
              bound = bound - 1
              other_bound = self.right + 1
            else
              other_bound = self.left - 1
            end
            
            DB.logger.info { "#{bound} == #{self.right} || #{bound} == #{self.left}" }

            # there would be no change
            return if bound == self.right || bound == self.left

            # we have defined the boundaries of two non-overlapping intervals,
            # so sorting puts both the intervals and their boundaries in order
            a, b, c, d = [self.left, self.right, bound, other_bound].sort

            new_parent = case position
              when :child;  target.id
              when :root;   'NULL'
              else          target.parent_id
            end

            # TODO : scope stuff for update
            self.dataset.update(
               "#{self.class.qualified_left_column_literal} = (CASE " +
                "WHEN #{self.class.qualified_left_column_literal} BETWEEN #{a} AND #{b} " +
                  "THEN #{self.class.qualified_left_column_literal} + #{d} - #{b} " +
                "WHEN #{self.class.qualified_left_column_literal} BETWEEN #{c} AND #{d} " +
                  "THEN #{self.class.qualified_left_column_literal} + #{a} - #{c} " +
                "ELSE #{self.class.qualified_left_column_literal} END), " +
              "#{self.class.qualified_right_column_literal} = (CASE " +
                "WHEN #{self.class.qualified_right_column_literal} BETWEEN #{a} AND #{b} " +
                  "THEN #{self.class.qualified_right_column_literal} + #{d} - #{b} " +
                "WHEN #{self.class.qualified_right_column_literal} BETWEEN #{c} AND #{d} " +
                  "THEN #{self.class.qualified_right_column_literal} + #{a} - #{c} " +
                "ELSE #{self.class.qualified_right_column_literal} END), " +
              "#{self.class.qualified_parent_column_literal} = (CASE " +
                "WHEN #{self.primary_key} = #{self.id} THEN #{new_parent} " +
                "ELSE #{self.class.qualified_parent_column_literal} END)"
            )
            target.refresh if target
            self.refresh
            #TODO: add after_move
          end
        end
      end
    end
  end
end
