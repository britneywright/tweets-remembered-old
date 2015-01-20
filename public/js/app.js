var faveTweets = angular.module('faveTweets',['ngResource','ngRoute']);

faveTweets.controller('TweetListController', ['$scope', 'Tweet',
  function($scope,Tweet) {
    $scope.tweets = Tweet.query();
    $scope.updateTweet = function(tweet){
      tweet.$update();
    };
  }]);

faveTweets.factory('Tweet',['$resource',function($resource){
  return $resource('/tweets/:id',{id: '@id'},{
    update: {method: 'PUT'}

  });
}]);