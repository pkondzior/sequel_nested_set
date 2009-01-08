module Sequel
  module Plugins
    module NestedSet
      # Apply the plugin to the model.
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
      end

      module DatasetMethods
        def nested_scope
          order(self.model_classes[nil].qualified_left_column)
        end

        def roots
          nested_scope.filter(self.model_classes[nil].qualified_parent_column => nil)
        end

        def leaves
          nested_scope.filter(self.model_classes[nil].qualified_right_column - self.model_classes[nil].qualified_left_column => 1)
        end
      end

      module ClassMethods
        def qualified_parent_column
          "#{self.implicit_table_name}__#{self.nested_set_options[:parent_column]}".to_sym
        end

        def qualified_left_column
          "#{self.implicit_table_name}__#{self.nested_set_options[:left_column]}".to_sym
        end

        def qualified_right_column
          "#{self.implicit_table_name}__#{self.nested_set_options[:right_column]}".to_sym
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
          self[self.nested_set_options[:left_column]]
        end

        # Getter of the right column
        def right
          self[self.nested_set_options[:right_column]]
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
          dataset.nested_scope.filter(self.primary_key => self.parent_id).first if self.parent_id
        end

        # Returns the dataset for all parent nodes and self
        def self_and_ancestors
          dataset.filter((self.class.qualified_left_column <= left) & (self.class.qualified_right_column  >= right))
        end

        # Returns the dataset for all children of the parent, including self
        def self_and_siblings
          dataset.nested_scope.filter(self.class.qualified_parent_column  => self.parent_id)
        end

        # Returns dataset for itself and all of its nested children
        def self_and_descendants
          dataset.nested_scope.filter((self.class.qualified_left_column >= left) & (self.class.qualified_right_column <= right))
        end

        # Filter for dataset that will exclude self object
        def without_self(dataset)
          dataset.nested_scope.filter(~{self.primary_key => self.id})
        end

        # Returns dataset for its immediate children
        def children
          dataset.nested_scope.filter(self.class.qualified_parent_column => self.id)
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

        def to_text
          self_and_descendants.map do |node|
            "#{'*'*(node.level+1)} #{node.class.inspect} (#{node.parent_id.inspect}, #{node.left}, #{node.right})"
          end.join("\n")
        end

        protected
        # on creation, set automatically lft and rgt to the end of the tree
        def set_default_left_and_right
          maxright = dataset.nested_scopemax(self.class.qualified_right_column) || 0
          # adds the new node to the right of all existing nodes
          self.left = maxright + 1
          self.right = maxright + 2
        end
      end
    end
  end
end
