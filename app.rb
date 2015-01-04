require 'sinatra'
require 'twitter'
require 'omniauth-twitter'
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'

configure do
  enable :sessions
end

configure :production do
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end

configure :development do
  DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/development.db")
end

helpers do
  def current_user?
    session[:uid]
  end

  def find_or_create_by_uid
    User.find{|f| f["uid"] == session[:uid]} || User.create(uid: session[:uid])
  end  
end

use OmniAuth::Builder do
  provider :twitter, ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET']
end

CLIENT = Twitter::REST::Client.new do |config|
  config.consumer_key        = ENV['CONSUMER_KEY']
  config.consumer_secret     = ENV['CONSUMER_SECRET']
end

class User
  include DataMapper::Resource
  property :id, Serial
  property :uid, Integer

  validates_presence_of :uid
  validates_uniqueness_of :uid
end

DataMapper.finalize

get '/' do
  erb :index
end

get '/users' do
  @users = User.all
  erb :users
end

get '/catalog' do
  halt(401,'Not Authorized') unless current_user?
  @user = find_or_create_by_uid
  erb :catalog
end

get '/login' do
  redirect to("/auth/twitter") unless current_user?
  @user = find_or_create_by_uid
  redirect to("/catalog")
end

get '/auth/twitter/callback' do
  session[:uid] = env['omniauth.auth']['uid']
  @user = find_or_create_by_uid
  redirect to("/catalog")
end

get '/auth/failure' do
  params[:message]
end

get '/logout' do
  session[:uid] = nil
  "You are now logged out"
end

not_found do
  halt(404,'URL not found.')
end