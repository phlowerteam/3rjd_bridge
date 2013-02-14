require 'rubygems'
require 'mysql2'
require 'active_record'
require 'yaml'
require 'logger'

def init
  ActiveRecord::Base.configurations["database_joomla"] = YAML::load(File.open('database_joomla.yml'))
  ActiveRecord::Base.configurations["database_3rose"] = YAML::load(File.open('database_3rose.yml'))
  ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'a'))
end

init

class JosDocman < ActiveRecord::Base
  set_table_name "jos_docman"
  establish_connection "database_joomla"
end

class JosCategory < ActiveRecord::Base
  establish_connection "database_joomla"
end

class Document < ActiveRecord::Base
  establish_connection "database_3rose"
end

class Category < ActiveRecord::Base
  establish_connection "database_3rose"
  belongs_to :parent, :class_name => 'Category', :foreign_key => 'parent_id'
  has_many :children, :class_name => 'Category', :foreign_key => 'parent_id'
end

p JosDocman.find(:all)
p JosCategory.find(:all)
p Document.find(:all)
p Category.find(:all)