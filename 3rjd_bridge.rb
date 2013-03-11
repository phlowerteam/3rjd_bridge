require 'rubygems'
require 'mysql2'
require 'active_record'
require 'yaml'
require 'logger'
require 'rest-client'
require 'json'
require 'net/ftp'

ROSE_USER     = 'writer'
ROSE_PASSWORD = 'writer'
ROSE_URL      = 'localhost:3000'

JDOCMAN_URL  = 'test.mirohost.net'
JDOCMAN_USER = 'admin'
JDOCMAN_PASS = 'admin'
JDOCMAN_DIR  = 'test.mirohost.net/dmdocuments'

IS_FTP_TRANSMITTING = false
TMP_FTP_FOLDER = 'tmp_ftp/'
#document local storage if ftp not use
LOCAL_STORAGE = '/home/alex/dmdocuments/'

def init
  if !(Dir.exist?(TMP_FTP_FOLDER))
    Dir.mkdir(TMP_FTP_FOLDER)
  end
  
  ActiveRecord::Base.configurations["database_joomla"] = YAML::load(File.open('database_joomla.yml'))
  ActiveRecord::Base.configurations["database_3rose"] = YAML::load(File.open('database_3rose.yml'))
  ActiveRecord::Base.logger = Logger.new(File.open('log.log', 'a'))
  #$stdout = File.open('log.log', 'a')

  response = RestClient.post(ROSE_URL + '/sign_in', :username => ROSE_USER, :password => ROSE_PASSWORD, :remember_me => true, :json => true)

  response = JSON.parse(response)
  return response['auth_token']
end

@auth_token = init

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

class State < ActiveRecord::Base
  establish_connection "database_3rose"
end

def synchronize_categories
  j_cats = JosCategory.where("section = 'com_docman'")
  r_cats = Category.where("external_id != 0")

  j_cats.each do |j_cat|
    if r_cat = Category.find_by_external_id(j_cat.id)
      #update
      RestClient.put(ROSE_URL + "/api/categories/#{r_cat.id}",\
                      :external_parent_id => j_cat.parent_id,\
                      :external_id        => r_cat.external_id,\
                      :parent_id          => r_cat.parent_id,\
                      :name               => j_cat.name,\
                      :description        => j_cat.description,\
                      :rate               => j_cat.ordering,\
                      :auth_token         => @auth_token)
    else
      #create
      RestClient.post(ROSE_URL + "/api/categories",\
                      :external_parent_id => j_cat.parent_id,\
                      :external_id        => j_cat.id,\
                      :parent_id          => 0,\
                      :name               => j_cat.name,\
                      :description        => j_cat.description,\
                      :rate               => j_cat.ordering,\
                      :auth_token         => @auth_token)
      #p "Error: cannot save category #{r_cat}" unless r_cat.save
    end
  end

  RestClient.post(ROSE_URL + "/api/categories/update_external_categories", :auth_token => @auth_token)

  #remove non existing joomla's categories on 3rose
  j_cats = j_cats ? j_cats : []
  r_cats = r_cats ? r_cats : []
  j_ids, r_ids = [], []
  j_cats.each{|j_cat| j_ids << j_cat.id}
  r_cats.each{|r_cat| r_ids << r_cat.external_id}
  r_ids_for_remove = r_ids - j_ids

  r_ids_for_remove.each do |id|
    if cat = Category.find_by_external_id(id)
      RestClient.delete(ROSE_URL + "/api/categories/" + cat.id.to_s + "?auth_token=" + @auth_token.to_s)
    end
  end
end

#synchronize_categories

def synchronize_documents
  r_cats = Category.where("external_id != 0")
  j_docs = j_docs ? j_docs : []
  ext_to_in_cat = {}
  r_cats.each{|cat| ext_to_in_cat[cat.external_id] = cat.id}
  #n, m = 0, 567
  n, m = 0, 1000
  j_docs = JosDocman.find(:all)[n..m]
  r_docs = Document.where("external_id != 0")
  j_docs = j_docs ? j_docs : []
  r_docs = r_docs ? r_docs : []
  j_ids, r_ids = [], []
  j_docs.each{|j_doc| j_ids << j_doc.id}
  r_docs.each{|r_doc| r_ids << r_doc.external_id}

  r_ids_for_upload = j_ids - r_ids
  p "[#{Time.now}] Total uploads: #{r_ids_for_upload}"
  r_ids_for_remove = r_ids - j_ids
  p "[#{Time.now}] Total removes: #{r_ids_for_remove}"

  #r_ids_for_upload = r_ids_for_upload.each{|id| ext_to_in_cat[id]}
  p r_ids_for_remove

  j_docs = JosDocman.find(r_ids_for_upload)
  j_docs.each do |j_doc|
    if IS_FTP_TRANSMITTING
      ftp = Net::FTP.new
      ftp.connect(JDOCMAN_URL, 21)
      ftp.login(JDOCMAN_USER, JDOCMAN_PASS)
      ftp.chdir(JDOCMAN_DIR)
      ftp.getbinaryfile(j_doc.dmfilename, TMP_FTP_FOLDER + j_doc.dmfilename, 1024)
      dmfilename = TMP_FTP_FOLDER + j_doc.dmfilename
      ftp.close
    else
      dmfilename = LOCAL_STORAGE + j_doc.dmfilename
    end

    p "[#{Time.now}] Current document: [id:#{j_doc.id} name:#{j_doc.dmname} file:#{j_doc.dmfilename}]"
    begin
      RestClient.post(ROSE_URL + "/api/documents",\
                      :category_id => ext_to_in_cat[j_doc.catid],\
                      :external_id => j_doc.id,\
                      :author => '',\
                      :name => j_doc.dmname,\
                      :description => j_doc.dmdescription,\
                      :file => File.new(dmfilename, 'rb'),\
                      :auth_token => @auth_token)
      FileUtils.rm(j_doc.dmfilename, :force => true) if IS_FTP_TRANSMITTING
    rescue
      p "ERROR: can't access to file #{dmfilename}"
    end
  end

  # p r_ids_for_remove
  # r_ids_for_remove.each do |external_id|
    # r_doc = Document.find_by_external_id(external_id)
    # RestClient.delete(ROSE_URL + "/api/documents/" + r_doc.id.to_s + "?auth_token=" + @auth_token.to_s)
  # end

end

synchronize_documents
