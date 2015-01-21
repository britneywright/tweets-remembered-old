require 'sinatra'
require 'twitter'
require 'omniauth-twitter'
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'
require 'dm-aggregates'
require 'dm-serializer'
require 'json'


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

  def tag_list=(names)
    tags.map(&:name).join(", ")
  end

  def tag_list=(names)
    self.tags = names.split(",").map do |n|
      Tag.first_or_create(:name => n.strip, :user_id => self.id)
    end
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
  property :id, Serial, :key => true
  property :uid, Integer, :precision => 20
  property :text, Text
  property :username, String
  property :screenname, String
  property :created_at, DateTime
  property :archived, Boolean, :default => false
  belongs_to :user
  has n, :tags, :through => Resource

  attr_accessor :tag_list

  def tag_list
    tags.map(&:name).join(", ")
  end

  def tag_list=(names)
    self.tags = names.split(",").map do |n|
      Tag.first_or_create(:name => n.strip, :user_id => self.user_id)
    end
  end

  def tagged_with
    Tag.first(:slug => slug).tweets
  end

  def uid_string
    uid.to_s
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

  redirect to("/")
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

#GET Returns all tweets
get '/tweets' do
  @tweets = User.first(:uid => session[:uid]).tweets.all(:order => [:uid.desc])
  @tweets.to_json(:methods => [:tags,:tag_list,:uid_string])
end


get '/tweets/:id/change' do
  @tweet = Tweet.get(params[:id])
  @tags = Tag.all
  erb :"tweet/edit"
end

get '/tweets/:id/show' do
  @tweet = Tweet.get(params[:id])
  erb :"tweet/show"
end

#GET - Returns single post
get '/tweets/:id' do
  @tweet = Tweet.get(params[:id])
  @tweet.to_json(:methods => [:tags,:tag_list,:uid_string])
end

#PUT - Updates existing tweet
# put '/tweets/:id' do
#   @tweet = Tweet.get(params[:id].to_i)
#   if @tweet.archived == true
#     @tweet.update(:archived => false)
#   else
#     @tweet.update(:archived => true)
#   end
#   if @tweet.save
#     @tweet.to_json
#   else
#     halt 500
#   end
# end

put '/tweets/:id' do
  begin
    params.merge! JSON.parse(request.env["rack.input"].read)
  rescue JSON::ParserError
    logger.error "Cannot parse request body."
  end  
  @tweet = Tweet.get(params[:id])
  if @tweet.update(:archived => params[:archived], :tag_list => params[:tag_list])
    status 201
  else
    halt 500
  end
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