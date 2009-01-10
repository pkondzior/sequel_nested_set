require File.join(File.dirname(__FILE__), "spec_helper")

describe "Sequel Nested Set" do

  describe "without scope" do
    
    before(:each) do
      prepare_nested_set_data
      @root = Client.filter(:name  => 'Top Level').first
      @node1 = Client.filter(:name  => 'Child 1').first
      @node2 = Client.filter(:name  => 'Child 2').first
      @node2_1 = Client.filter(:name => 'Child 2.1').first
      @node3 = Client.filter(:name => 'Child 3').first
      @root2 = Client.filter(:name  => 'Top Level 2').first
    end

    describe "ClassMethods" do

      it "should have nested_set_options" do
        Client.should respond_to(:nested_set_options)
      end

      it "should have default options :left_column, :right_column, :parent_column, :dependent and :scope" do
        Client.nested_set_options[:left_column].should == :lft
        Client.nested_set_options[:right_column].should == :rgt
        Client.nested_set_options[:parent_column].should == :parent_id
        Client.nested_set_options[:dependent].should == :delete_all
        Client.nested_set_options[:scope].should be_nil
      end

      it "should have qualified column methods" do
        Client.qualified_parent_column.should == :clients__parent_id
        Client.qualified_left_column.should == :clients__lft
        Client.qualified_right_column.should == :clients__rgt
      end

      it "should have roots that contains all root nodes" do
        roots = Client.roots.all
        roots.should == Client.filter(:parent_id => nil).all
        roots.should == [@root, @root2]
      end
  
      it "should have root that will be root? => true" do
        Client.roots.first.root?.should be_true
      end

      it "should have all leaves" do
        leaves = Client.leaves.all
        leaves.should == Client.nested.filter(:rgt - :lft => 1).all
        leaves.should == [@node1, @node2_1, @node3, @root2]
      end

      it "should have root" do
        Client.root.should == @root
      end

      it "should have to_text method that returns whole tree from all root nodes as text" do
        Client.to_text.should == "* Client (nil, 1, 10)\n** Client (1, 2, 3)\n** Client (1, 4, 7)\n*** Client (3, 5, 6)\n** Client (1, 8, 9)\n* Client (nil, 11, 12)"
      end

      it "should have to_text method that returns whole tree from all root nodes as text and should be able to pass block" do
        Client.to_text { |node| node.name }.should == "* Top Level (nil, 1, 10)\n** Child 1 (1, 2, 3)\n** Child 2 (1, 4, 7)\n*** Child 2.1 (3, 5, 6)\n** Child 3 (1, 8, 9)\n* Top Level 2 (nil, 11, 12)"
      end
    end

    describe "InstanceMethods" do

      it "should have nested_set_options" do
        @root.class.should respond_to(:nested_set_options)
      end

      it "should have parent, left, right getter based on nested set config" do
        node = Client.new.update_all(:parent_id => nil, :lft => 1, :rgt => 2)
        node.left.should == node[node.class.nested_set_options[:left_column]]
        node.right.should == node[node.class.nested_set_options[:right_column]]
        node.parent_id.should == node[node.class.nested_set_options[:parent_column]]
      end

      it "should have parent, left, right setter based on nested set config" do
        node = Client.new
        node.send(:left=, 1)
        node.send(:right=, 2)
        node.send(:parent_id=, 69)
        node.left.should == node[node.class.nested_set_options[:left_column]]
        node.right.should == node[node.class.nested_set_options[:right_column]]
        node.parent_id.should == node[node.class.nested_set_options[:parent_column]]
      end

      it "should parent, left and right setters be protected methods" do
        Client.new.protected_methods.include?("left=").should be_true
        Client.new.protected_methods.include?("right=").should be_true
        Client.new.protected_methods.include?("parent_id=").should be_true
      end

      it "shoud have faild on new when passing keys configured as right_column, left_column, parent_column" do
        lambda { Client.new(Client.nested_set_options[:left_column] => 1) }.should raise_error(Sequel::Error)
        lambda { Client.new(Client.nested_set_options[:right_column] => 2) }.should raise_error(Sequel::Error)
        lambda { Client.new(Client.nested_set_options[:parent_column] => nil) }.should raise_error(Sequel::Error)
      end

      it "Client.new with {:left => 1, :right => 2, :parent_id => nil} should raise NoMethodError exception" do
        lambda { Client.new({:left => 1, :right => 2, :parent_id => nil}) }.should raise_error(Sequel::Error)
      end

      it "should have nested_set_options equal to Model.nested_set_options" do
        @root.nested_set_options.should == Client.nested_set_options
      end

      it "should have nodes that have common root" do
        @node1.root.should == @root
      end

      it "should have nodes that have their parent" do
        @node2_1.parent.should == @node2
      end

      it "should have leaf that will be true leaf?" do
        @root.leaf?.should_not be_true
        @node2_1.leaf?.should be_true
      end

      it "should have child that will be true child?" do
        @root.child?.should_not be_true
        @node2_1.child?.should be_true
      end

      it "should have <=> method" do
        @root.should respond_to(:<=>)
      end

      it "Should order by left column" do
        (@node1 <=> @node2).should == -1
      end

      it "should have level of node" do
        @root.level.should == 0
        @node1.level.should == 1
        @node2.level.should == 1
        @node2_1.level.should == 2
      end

      it "should have parent relation" do
        @node2_1.parent.should == @node2
      end

      it "should have self_and_sibling that have self node and all its siblings" do
        @root.self_and_siblings.all.should == [@root, @root2]
        @node1.self_and_siblings.all.should == [@node1, @node2, @node3]
      end

      it "should have siblings of node withot itself" do
        @root.siblings.all.should == [@root2]
        @node1.siblings.all.should == [@node2, @node3]
      end

      it "should have self_and_ancestors that have self node and all its ancestors" do
        @root.self_and_ancestors.all.should == [@root]
        @node1.self_and_ancestors.all.should == [@root, @node1]
      end

      it "should have ancestors of node withot itself" do
        @root.ancestors.all.should == []
        @node1.ancestors.all.should == [@root]
      end

      it "should have self_and_descendants that have self node and all its descendents" do
        @root.self_and_descendants.all.should == [@root, @node1, @node2, @node2_1, @node3]
        @node2.self_and_descendants.all.should == [@node2, @node2_1]
        @node2_1.self_and_descendants.all.should == [@node2_1]
      end

      it "should have descendents that are children and nested children wihout itself" do
        @root.descendants.all.should == [@node1, @node2, @node2_1, @node3]
        @node2.descendants.all.should == [@node2_1]
        @node2_1.descendants.all.should == []
      end

      it "should have children that returns set of only node immediate children" do
        @root.children.all.should == [@node1, @node2, @node3]
        @node2.children.all.should == [@node2_1]
        @node2_1.children.all.should == []
      end

      it "should have leaves that are set of all of node nested children which do not have children" do
        @root.leaves.all.should == [@node1, @node2_1, @node3]
        @node2.leaves.all.should == [@node2_1]
        @node2_1.leaves.all.should == []
      end

      it "should be able to get left sibling" do
        @node2.left_sibling.should == @node1
        @node3.left_sibling.should == @node2
        @node1.left_sibling.should be_nil
      end

      it "should be able to get proper right sibling" do
        @node1.right_sibling.should == @node2
        @node2.right_sibling.should == @node3
        @node3.right_sibling.should be_nil
      end

      it "should @root and @node be in same scope" do
        @root.same_scope?(@node).should be_true
      end

      it "should @root and @root_in_other_scope be in different scope" do
    
      end

      it "should have node_x.is_or_is_descendant_of?(node_y) that will return proper boolean value" do
        @node1.is_or_is_descendant_of?(@root).should be_true
        @node2_1.is_or_is_descendant_of?(@root).should be_true
        @node2_1.is_or_is_descendant_of?(@node2).should be_true
        @node2.is_or_is_descendant_of?(@node2_1).should be_false
        @node2.is_or_is_descendant_of?(@node1).should be_false
        @node1.is_or_is_descendant_of?(@node1).should be_true
      end

      it "should have node_x.is_ancestor_of?(node_y) that will return proper boolean value" do
        @node1.is_descendant_of?(@root).should be_true
        @node2_1.is_descendant_of?(@root).should be_true
        @node2_1.is_descendant_of?(@node2).should be_true
        @node2.is_descendant_of?(@node2_1).should be_false
        @node2.is_descendant_of?(@node1).should be_false
        @node1.is_descendant_of?(@node1).should be_false
      end

      it "should have node_x.is_ancestor_of?(node_y) that will return proper boolean value" do
        @root.is_ancestor_of?(@node1).should be_true
        @root.is_ancestor_of?(@node2_1).should be_true
        @node2.is_ancestor_of?(@node2_1).should be_true
        @node2_1.is_ancestor_of?(@node2).should be_false
        @node1.is_ancestor_of?(@node2).should be_false
        @node1.is_ancestor_of?(@node1).should be_false
      end

      it "should have node_x.is_or_is_ancestor_of?(node_y) that will return proper boolean value" do
        @root.is_or_is_ancestor_of?(@node1).should be_true
        @root.is_or_is_ancestor_of?(@node2_1).should be_true
        @node2.is_or_is_ancestor_of?(@node2_1).should be_true
        @node2_1.is_or_is_ancestor_of?(@node2).should be_false
        @node1.is_or_is_ancestor_of?(@node2).should be_false
        @node1.is_or_is_ancestor_of?(@node1).should be_true
      end

      it "should have node2 with left sibling as node1 and node3 with left sibling node2" do
        @node2.left_sibling.should == @node1
        @node3.left_sibling.should == @node2
      end

      it "should have root without left sibling" do
        @root.left_sibling.should be_nil
      end

      it "should have node2_1 without left sibling" do
        @node2_1.left_sibling.should be_nil
      end

      it "should have node1 without left sibling" do
        @node1.left_sibling.should be_nil
      end

      it "should have node2 with right sibling as node3 and node1 with right sibling node2" do
        @node2.right_sibling.should == @node3
        @node1.right_sibling.should == @node2
      end

      it "should have root with right sibling as root2 and root2 with without right sibling" do
        @root.right_sibling.should == @root2
        @root2.right_sibling.should be_nil
      end

      it "should have node2_1 without right sibling" do
        @node2_1.right_sibling.should be_nil
      end

      it "should have node3 without right sibling" do
        @node3.right_sibling.should be_nil
      end

      it "should have to_text method that returns whole tree of instance node as text" do
        @root.to_text.should == "* Client (nil, 1, 10)\n** Client (1, 2, 3)\n** Client (1, 4, 7)\n*** Client (3, 5, 6)\n** Client (1, 8, 9)"
      end

      it "should have to_text method that returns whole tree of instance node as text and should be able to pass block" do
        @root.to_text { |node| node.name }.should == "* Top Level (nil, 1, 10)\n** Child 1 (1, 2, 3)\n** Child 2 (1, 4, 7)\n*** Child 2.1 (3, 5, 6)\n** Child 3 (1, 8, 9)"
      end

      it "should node2 be able to move to the left" do
        @node2.move_left
        @node2.left_sibling.should be_nil
        @node2.right_sibling.should == @node1.refresh
        Client.valid?.should be_true
      end

      it "should node2 be able to move to the right" do
        @node2.move_right
        @node2.right_sibling.should be_nil
        @node2.left_sibling.should == @node3.refresh
        Client.valid?.should be_true
      end

      it "should node3 be able to move to the left of node1" do
        @node3.move_to_left_of(@node1)
        @node3.left_sibling.should be_nil
        @node3.right_sibling.should == @node1.refresh
        Client.valid?.should be_true
      end

      it "should node1 be able to move to the right of node1" do
        @node1.move_to_right_of(@node3)
        @node1.right_sibling.should be_nil
        @node1.left_sibling.should == @node3.refresh
        Client.valid?.should be_true
      end
  
      it "should node2 be able to became root" do
        @node2.move_to_root
        @node2.parent.should be_nil
        @node2.level.should == 0
        @node2_1.level.should == 1
        @node2.left == 1
        @node2.right == 4
        Client.valid?.should be_true
      end
  
      it "should node1 be able to move to child of node3" do
        @node1.move_to_child_of(@node3)
        @node1.parent_id.should == @node3.id
        Client.valid?.should be_true
      end

      it "should be able to move new node to the end of root children" do
        child = Client.create(:name => 'New Child')
        child.move_to_child_of(@root)
        @root.children.last.should == child
        Client.valid?.should be_true
      end
  
      it "should be able to move node2 as child of node1" do
        @node2.left.should == 4
        @node2.right.should == 7
        @node1.left.should == 2
        @node1.right.should == 3
        @node2.move_to_child_of(@node1)
        @node2.parent_id.should == @node1.id
        Client.valid?.should be_true
        @node2.left.should == 3
        @node2.right.should == 6
        @node1.left.should == 2
        @node1.right.should == 7
      end

      it "should be able to move root node to child of new node" do
        @root2.left.should == 11
        @root2.right.should == 12

        root3 = Client.create(:name => 'New Root')
        root3.left.should == 13
        root3.right.should == 14

        @root2.move_to_child_of(root3)

        Client.valid?.should be_true
        @root2.parent_id.should == root3.id

        @root2.left.should == 12
        @root2.right.should == 13

        root3.left.should == 11
        root3.right.should == 14
      end
  
      it "should be able to move root node to child of new node" do
        @root.left.should == 1
        @root.right.should == 10
        @node2_1.left.should == 5
        @node2_1.right.should == 6
    
        root3 = Client.create(:name => 'New Root')
        @root.move_to_child_of(root3)
        Client.valid?.should be_true
        @root.parent_id.should == root3.id

        @root.left.should == 4
        @root.right.should == 13

        @node2_1.refresh
        @node2_1.left.should == 8
        @node2_1.right.should == 9
      end

      it "should be able to rebuild whole tree" do
        node1 = Client.create(:name => 'Node-1')
        node2 = Client.create(:name => 'Node-2')
        node3 = Client.create(:name => 'Node-3')

        node2.move_to_child_of node1
        node3.move_to_child_of node1

        output = Client.roots.last.to_text
        Client.update('lft = null, rgt = null')
        Client.rebuild!

        Client.roots.last.to_text.should == output
      end
  
      it "should be invalid which lft = null" do
        Client.valid?.should be_true
        Client.update("lft = NULL")
        Client.valid?.should be_false
      end

      it "should be invalid which rgt = null" do
        Client.valid?.should be_true
        Client.update("rgt = NULL")
        Client.valid?.should be_false
      end
  
      it "should be valid with mising intermediate node" do
        Client.valid?.should be_true
        @node2.destroy
        Client.valid?.should be_true
      end
  
      it "should be invalid with overlapping right nodes" do
        Client.valid?.should be_true
        @root2[:lft] = 0
        @root2.save
        Client.valid?.should be_false
      end

      it "should be able to rebild" do
        Client.valid?.should be_true
        before_text = Client.root.to_text
        Client.update('lft = NULL, rgt = NULL')
        Client.rebuild!
        Client.valid?.should be_true
        before_text.should == Client.root.to_text
      end

      it "shold be able to move for sibbling" do
        @node2.move_possible?(@node1).should be_true
      end

      it "shold not be able to move for itself" do
        @root.move_possible?(@root).should be_false
      end

      it "should not be able to move for parent" do
        @root.descendants.each do |descendant_node|
          @root.move_possible?(descendant_node).should be_false
          descendant_node.move_possible?(@root).should be_true
        end
      end

      it "should be correct is_or_is_ancestor_of?" do
        [@node1, @node2, @node2_1, @node3].each do |node|
          @root.is_or_is_ancestor_of?(node).should be_true
        end
        @root.is_or_is_ancestor_of?(@root2).should be_false
      end
  
      it "should be invalid left_and_rights_valid? for nil lefts" do
        Client.left_and_rights_valid?.should be_true
        @node2[:lft] = nil
        @node2.save
        Client.left_and_rights_valid?.should be_false
      end

      it "should be invalid left_and_rights_valid? for nil rights" do
        Client.left_and_rights_valid?.should be_true
        @node2[:rgt] = nil
        @node2.save
        Client.left_and_rights_valid?.should be_false
      end

      it "should return true for left_and_rights_valid? when node lft is equal for root lft" do
        Client.left_and_rights_valid?.should be_true
        @node2[:lft] = @root[:lft]
        @node2.save
        Client.left_and_rights_valid?.should be_false
      end

      it "should return true for left_and_rights_valid? when node rgt is equal for root rgt" do
        Client.left_and_rights_valid?.should be_true
        @node2[:rgt] = @root[:rgt]
        @node2.save
        Client.left_and_rights_valid?.should be_false
      end

      it "should be valid after moving dirty nodes" do
        n1 = Client.create
        n2 = Client.create
        n3 = Client.create
        n4 = Client.create

        n2.move_to_child_of(n1)
        Client.valid?.should be_true

        n3.move_to_child_of(n1)
        Client.valid?.should be_true

        n4.move_to_child_of(n2)
        Client.valid?.should be_true
      end
    end
  end

  describe "wiht scope" do
    describe "ClassMethods" do
      it "should be no duplicates for columns accross different scopes" do

      end

      it "should have all roots valid accross different scopes" do

      end

      it "should have multi scope" do

      end

      it "should be able to rebuild! accross different scopes" do
        
      end

      it "should have same_scope? true for nodes in the same scope" do

      end

      it "should have equal nodes in the same scope" do

      end

      #  def test_multi_scoped_no_duplicates_for_columns?
      #    assert_nothing_raised do
      #      Note.no_duplicates_for_columns?
      #    end
      #  end
      #
      #  def test_multi_scoped_all_roots_valid?
      #    assert_nothing_raised do
      #      Note.all_roots_valid?
      #    end
      #  end
      #
      #  def test_multi_scoped
      #    note1 = Note.create!(:body => "A", :notable_id => 2, :notable_type => 'Category')
      #    note2 = Note.create!(:body => "B", :notable_id => 2, :notable_type => 'Category')
      #    note3 = Note.create!(:body => "C", :notable_id => 2, :notable_type => 'Default')
      #
      #    assert_equal [note1, note2], note1.self_and_siblings
      #    assert_equal [note3], note3.self_and_siblings
      #  end
      #
      #  def test_multi_scoped_rebuild
      #    root = Note.create!(:body => "A", :notable_id => 3, :notable_type => 'Category')
      #    child1 = Note.create!(:body => "B", :notable_id => 3, :notable_type => 'Category')
      #    child2 = Note.create!(:body => "C", :notable_id => 3, :notable_type => 'Category')
      #
      #    child1.move_to_child_of root
      #    child2.move_to_child_of root
      #
      #    Note.update_all('lft = null, rgt = null')
      #    Note.rebuild!
      #
      #    assert_equal Note.roots.find_by_body('A'), root
      #    assert_equal [child1, child2], Note.roots.find_by_body('A').children
      #  end
      #
      #  def test_same_scope_with_multi_scopes
      #    assert_nothing_raised do
      #      notes(:scope1).same_scope?(notes(:child_1))
      #    end
      #    assert notes(:scope1).same_scope?(notes(:child_1))
      #    assert notes(:child_1).same_scope?(notes(:scope1))
      #    assert !notes(:scope1).same_scope?(notes(:scope2))
      #  end
      #
      #  def test_quoting_of_multi_scope_column_names
      #    assert_equal ["\"notable_id\"", "\"notable_type\""], Note.quoted_scope_column_names
      #  end
      #
      #  def test_equal_in_same_scope
      #    assert_equal notes(:scope1), notes(:scope1)
      #    assert_not_equal notes(:scope1), notes(:child_1)
      #  end
      #
      #  def test_equal_in_different_scopes
      #    assert_not_equal notes(:scope1), notes(:scope2)
      #  end
    end

    describe "InstanceMethods" do

    end
  end

end

