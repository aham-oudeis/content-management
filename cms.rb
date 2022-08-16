require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'psych'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

def create_document(name, content='')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def file_not_legit?(filename)
  legit_files = ['.txt', '.md']
  !legit_files.include?(File.extname(filename))
end

def error_message(filename)
  salt = 'a'
  filename = salt + filename

  if file_not_legit?(filename)
    "Files must be either plain text (.txt) or markdown (.md)."
  elsif File.basename(filename, '.*').length < 2
    "Filename must have at least one character."
  elsif File.exist?(File.join(data_path, filename))
    "#{filename} already exists. Please enter a different name."
  end
end

def render_markdown(content)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(content)
end

def load_file(filepath)
  content = File.read(filepath)

  case File.extname(filepath)
  when '.md'
      render_markdown(content)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  end
end

def files_in(path)
  Dir.glob(path).map do |filename|
    File.basename(filename)
  end
end

def users_file_path
  file_location = '..'
  file_location = '../test' if ENV["RACK_ENV"] == 'test'
  file_path = File.expand_path(file_location, __FILE__)
  File.join(file_path, 'users.yml')
end

def valid_credential?(username, password)
  users = Psych.load_file(users_file_path)
  if users[username]
    BCrypt::Password.new(users[username]) == password
  end
end

def signed_in?
  session.key?(:username)
end

def redirect_unless_signed_in
  unless signed_in?
    session['flash_error'] = "You must be signed in to do that."
    redirect '/'
  end
end

# index page
get '/' do
  pattern = File.join(data_path, '*')
  @files = files_in(pattern)

  erb :home, layout: :layout
end

# view each file
get '/:name' do
  filepath = File.join(data_path, params['name'])
  
  if File.exist?(filepath)
    load_file(filepath)
  else
    session['flash_error'] = "#{params['name']} does not exist."
    redirect '/'
  end
end

# render a new file form
get '/new/' do
  redirect_unless_signed_in

  erb :new_file, layout: :layout
end

# create a new file
post '/create' do
  redirect_unless_signed_in

  filename = params['docu_name'].strip
  
  filename_error = error_message(filename)

  if filename_error
    session['flash_error'] = filename_error
    status 422
    erb :new_file, layout: :layout
  else
    create_document filename
    session['flash_success'] = "#{filename} was created."
    redirect '/'
  end
end

# render an edit file form
get '/:name/edit' do
  filepath = File.join(data_path, params['name'])

  if File.exist?(filepath)
    @name = params['name']
    @content = File.read(filepath)
    redirect_unless_signed_in
    erb :edit_file
  else
    session['flash_error'] = "#{@name} does not exist."
    redirect '/'
  end
end

# update file
post '/:name' do
  redirect_unless_signed_in

  filepath = File.join(data_path, params['name'])

  @new_content = params['new_content']
  File.write(filepath, @new_content)

  session['flash_success'] = "The file #{params['name']} has been updated."

  redirect '/'
end

# delete a file
post '/:name/delete' do
  filepath = File.join(data_path, params['name'])

  if File.exist?(filepath)
    redirect_unless_signed_in
    FileUtils.remove_file(filepath)
    session['flash_success'] = "#{params['name']} has been deleted."
  else
    session['flash_error'] = "#{params['name']} does not exist."
  end

  redirect '/'
end

# render the sign in page
get '/users/signin' do
  erb :sign_in, layout: :layout
end

# as the user signs in
post '/users/signin' do
  user_name = params['username']
  password = params['password']
 
  if valid_credential?(user_name, password)
    session['flash_success'] = "Welcome, #{user_name}!"
    session['username'] = user_name
    redirect '/'
  else
    session['flash_error'] = "Invalid Credentials! Try again!"
    status 422
    erb :sign_in, layout: :layout
  end
end

# sign out
get '/:user/signout' do
  session.delete('username')
  session['flash_success'] = "You've been signed out."
  redirect '/'
end
