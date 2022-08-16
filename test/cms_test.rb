ENV['RACK_ENV'] = 'test'

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative '../cms'

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def create_document(name, content='')
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def create_users
    File.open(users_file_path, "w") do |file|
      file.write("admin: $2a$12$b9qmXnPfZ7LlZodI3ODYeuNY8lr0sVaVx.JAeJoiRFDrmOv9400OK\nnilin: $2a$12$E2nVg0UW.YpS9LhqXiBtUuxE/.5O5mLle/1bxnwAwGEBtovxDyP/q")
    end
  end

  def admin_session
    { "rack.session" => { username: "admin" }}
  end

  def setup
    FileUtils.mkdir_p(data_path)
    create_users
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.remove_file(users_file_path)
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"
 
    get '/'

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'changes.txt'
  end

  def test_changes
    create_document "changes.txt", "This is just a test."
  
    get '/changes.txt'

    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']
    assert_equal "This is just a test.", last_response.body
  end

  def test_non_existent_file
    get '/bullshit.txt'

    assert_equal 302, last_response.status
    
    get last_response['Location']

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'bullshit.txt does not exist.'

    get '/'

    refute_includes last_response.body, 'bullshit.txt does not exist.'
  end

  def test_viewing_markdown_document
    create_document "about.md", "# Ruby is..."

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_edit_file
    create_document "changes.txt", "The old content."

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, "The old content."
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_edit_file_no_sign_in
    create_document "changes.txt", "The old content."

    get "/changes.txt/edit"
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, "You must be signed in to do that."
  end

  def test_updating_file
    create_document "changes.txt", "The old content."

    post "/changes.txt", { new_content: "Some new content." }, admin_session
    assert_equal 302, last_response.status
    
    get last_response['Location']

    assert_equal 200, last_response.status
    assert_includes last_response.body, "changes.txt has been updated."

    get '/changes.txt'
    assert_includes last_response.body, "Some new content."
    refute_includes last_response.body, "The old content."
  end

  def test_updating_file_no_sign_in
    create_document "changes.txt", "The old content."

    post "/changes.txt", { new_content: "Some new content." }
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, "You must be signed in to do that."
  end

  def test_view_new_document
    get '/new/', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_create_new_documents
    post '/create', { docu_name: "test.txt" }, admin_session

    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test.txt was created."

    get '/'
    assert_includes last_response.body, 'test.txt'
  end

  def test_create_new_document_no_sign_in
    post '/create', { docu_name: "test.txt" }

    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, "You must be signed in to do that."
  end

  def test_create_document_without_extension
    post  '/create', { docu_name: '' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Files must be either plain text (.txt) or markdown (.md)."
  end

  def test_create_document_without_name
    post '/create', { docu_name: '.txt' }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Filename must have at least one character."
  end

  def test_deleting_document
    create_document "test.txt"

    post "/test.txt/delete", {} , admin_session

    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "test.txt has been deleted."

    get "/"
    refute_includes last_response.body, "test.txt"
  end

  def test_deleting_document_no_sign_in
    create_document "test.txt"

    post "/test.txt/delete", {} 
  
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_includes last_response.body, "You must be signed in to do that."
  end

  def test_before_sign_in
    get '/'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_sign_in_form
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input type="text" name="username")
    assert_includes last_response.body, %q(<input type="text" name="password" value="")
  end

  def test_unsuccessful_sign_in
    post "/users/signin", { username: "someone", password: "something" }

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials! Try again!"
    assert_includes last_response.body, %q(<input type="text" name="username")
    assert_includes last_response.body, %q(<input type="text" name="password" value="")
  end

  def test_sign_in_success
    post "/users/signin", { username: "admin", password: "secret" }

    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Welcome, admin!"
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, "Sign Out"
  end

  def test_sign_out
    post "/users/signin", { username: "admin", password: "secret" }

    get last_response['Location']

    get '/admin/signout'
    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You've been signed out."

    get '/'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_sign_in_from_yml
    post "/users/signin", { username: "nilin", password: "lifeboat" }
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Welcome, nilin!"
  end
end