require File.join(File.dirname(__FILE__), "spec_helper")

describe "Sequel Nested Set Class" do
  before(:each) do
    ClientMock.reset
    @root = Client.filter(:name  => 'Top Level').first
    @node1 = Client.filter(:name  => 'Child 1').first
    @node2 = Client.filter(:name  => 'Child 2').first
    @node2_1 = Client.filter(:name => 'Child 2.1').first
    @node3 = Client.filter(:name => 'Child 3').first
    @root2 = Client.filter(:name  => 'Top Level 2').first
  end

  it "should have nested_set_options" do
    Client.should respond_to :nested_set_options
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
end

describe "Sequel Nested Set Instance" do

  before(:each) do
    ClientMock.reset
    @root = Client.filter(:name  => 'Top Level').first
    @node1 = Client.filter(:name  => 'Child 1').first
    @node2 = Client.filter(:name  => 'Child 2').first
    @node2_1 = Client.filter(:name  => 'Child 2.1').first
    @node3 = Client.filter(:name => 'Child 3').first
    @root2 = Client.filter(:name  => 'Top Level 2').first
  end

  it "should have nested_set_options" do
    @root.class.should respond_to :nested_set_options
  end

  it "should have parent, left, right getter based on nested set config" do
    node = Client.new(:parent_id => nil, :lft => 1, :rgt => 2)
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

  it "Client.new with {:left => 1, :right => 2, :parent_id => nil} should raise NoMethodError exception" do
    
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
    @root.should respond_to :<=>
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

  it "should have to_text method" do
    @root.to_text.should == "* Client (nil, 1, 10)\n** Client (1, 2, 3)\n** Client (1, 4, 7)\n*** Client (3, 5, 6)\n** Client (1, 8, 9)"
  end

  it "should node2 be able to move left" do
    @node2.move_left
    @node2.left_sibling.should be_nil
    @node2.right_sibling.should == @node1.refresh
    Client.valid?.should be_true
  end

  it "should node2 be able to move right" do
    @node2.move_right
    @node2.right_sibling.should be_nil
    @node2.left_sibling.should == @node3.refresh
    Client.valid?.should be_true
  end

end

