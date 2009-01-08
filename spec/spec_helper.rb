require 'rubygems'
require 'spec'
require 'sequel'

require File.dirname(__FILE__) + '/../lib/sequel_nested_set'

DB = Sequel.sqlite # memory database

DB.create_table :clients do # Create a new table
  primary_key :id
  column :name, :text
  column :parent_id, :integer
  column :lft, :integer
  column :rgt, :integer
end

class Client < Sequel::Model
  is :nested_set
end

DB[:clients] << {"name"=>"Top Level 2", "lft"=>11, "id"=>6, "rgt"=>12}
DB[:clients] << {"name"=>"Child 2.1", "lft"=>5, "id"=>4, "parent_id"=>3, "rgt"=>6}
DB[:clients] << {"name"=>"Child 1", "lft"=>2, "id"=>2, "parent_id"=>1, "rgt"=>3}
DB[:clients] << {"name"=>"Top Level", "lft"=>1, "id"=>1, "rgt"=>10}
DB[:clients] << {"name"=>"Child 2", "lft"=>4, "id"=>3, "parent_id"=>1, "rgt"=>7}
DB[:clients] << {"name"=>"Child 3", "lft"=>8, "id"=>5, "parent_id"=>1, "rgt"=>9}

