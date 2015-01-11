require 'sinatra'
require 'twitter'
require 'omniauth-twitter'
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'
require 'dm-aggregates'
require 'dm-serializer'

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

  has n, :tags
  has n, :tweets

  attr_accessor :fetch_tweets, :tag_list 

  def fetch_tweets
    fave_count = self.tweets.length
    if self.tweets.length == 0
      tweet_params({:count => 200})
      fetch_tweets
    else
      tweet_params({:count => 200, :max_id => (self.tweets.min(:uid)-1)})
      tweet_params({:count => 200, :since_id => self.tweets.max(:uid)})
      if fave_count == self.tweets.length
        return
      else
        fetch_tweets
      end
    end
  end

  def tag_list
    tags.map(&:name).join(", ")
  end

  def tag_list=(names)
    tags.map(&:name).join(", ")
  end

  def tweet_params(query_options)
    CLIENT.favorites(self.uid,options=query_options).each do |tweet|
      self.tweets.push(Tweet.first_or_create(:uid => tweet.id, :text => tweet.text, :username => tweet.user.name, :screenname => tweet.user.screen_name, :created_at => tweet.created_at, :user_id => self.id))
    end
  end 
end

class Tag
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :slug, String, default: -> r,p { r.to_slug }
  belongs_to :user
  has n, :tweets, :through => Resource

  def to_slug
    name.downcase.gsub(/\W/,'-').squeeze('-').chomp('-') 
  end
end

class Tweet
  include DataMapper::Resource
  property :id, Serial
  property :uid, Integer
  property :text, Text
  property :username, String
  property :screenname, String
  property :created_at, DateTime
  property :archived, String, :default => false
  belongs_to :user
  has n, :tags, :through => Resource

  def tagged_with
    Tag.first(:slug => slug).tweets
  end
end

DataMapper.finalize

get '/' do
  if current_user?
    @user = User.first(:uid => session[:uid])
    erb :index
  else
    erb :welcome
  end
end

get '/users' do
  @users = User.all
  erb :users
end

get '/catalog' do
  halt(401,'Not Authorized') unless current_user?
  @user = User.first(:uid => session[:uid])
  @user.fetch_tweets
  erb :catalog
end

post '/catalog' do
  @user = find_or_create_by_uid
  @user.fetch_tweets
end

get '/tags' do
  @tags = User.first(:uid => session[:uid]).tags
  erb :"tags/index"
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