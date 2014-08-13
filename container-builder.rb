#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require "rubygems"
require "bundler/setup"

require "git"
require "erb"
require "readline"
require 'fileutils'
require 'socket'
require 'ipaddr'
require 'optparse'

class Repository
  attr_accessor :git
  attr_reader :vm_addr, :basedir, :docker_user, :app_name, :app_repo, :base_image, :docker_registry

  def self.create(args)
    repo = self.new(args)
    `git init --bare #{repo.origin_repo_path}`
    repo.git = Git.bare(repo.origin_repo_path)
    repo.git.config('receive.denyCurrentBranch', 'ignore')

    Dir.chdir(repo.git.repo.path + "/hooks") do
      erb = ERB.new(DATA.read)
      File.open('pre-receive', 'w') do |f|
        f.puts(erb.result(repo.create_binding))
        f.chmod(0755)
      end
    end

    return repo
  end

  def initialize(args)
    @vm_addr     = args[:vm_addr]
    @basedir     = args[:basedir]
    @docker_user = args[:docker_user]
    @app_name = args[:app_name]
    @app_repo = args[:app_repo]
    @base_image = args[:base_image]
    @docker_registry = args[:docker_registry]
  end

  def create_binding
    binding
  end

  def serial
    @serial ||= `ls #{@basedir} | wc -l`
  end

  def reponame
    sprintf("container-%04d", serial)
  end

  def origin_repo_path
    "#{basedir}/#{reponame}.git"
  end

  def origin_repo_url
    "#{origin_repo_path}"
  end

  def port
    sprintf("5%04d", serial)
  end

  def dir
    git.dir
  end

  def add_remote(name, address)
    git.add_remote(name, "root@#{address}:/root/git-repos/#{reponame}.git")
  end
end

opt = OptionParser.new
OPTS = {}

opt.banner = 'application_name [-options]'
opt.on('-b BASE_IMAGE=ubuntu') {|v| OPTS[:base_image] = v || 'ubuntu' }
opt.on('-d DOCKER_REGISTRY=157.1.15.168:80') 

opt.parse!(ARGV)

if ARGV.length == 0
  opt.summarize do |line|
    puts line
  end
  exit 1
end

OPTS[:base_image] ||= 'ubuntu'
OPTS[:docker_registry] ||= '157.1.15.168:80'

app_name = ARGV[0]

repo = Repository.create(
  vm_addr:  'localhost',
  basedir:  File.expand_path('~/managed_repos'),
  docker_user: "",
  app_name: app_name,
  app_repo: '',
  base_image: OPTS[:base_image],
  docker_registry: OPTS[:docker_registry]
)

puts <<MESSAGE
Repository created!
#{repo.origin_repo_path}
Add remote and push to it then starting to build.

Add remote ex)
  git remote add container-builder <builder host>:#{repo.reponame}
or
  git remote add container-builder file://#{repo.origin_repo_path}

Push it)
  git push container-builder <branch>:<environment>

MESSAGE

__END__
#!/bin/bash
set -eo pipefail
# set -x

if [ -f is_running ];then
  echo "-----> Killing current container"
  job=`cat is_running`
  sudo docker kill $job
fi

while read old_rev new_rev ref_name
do

# export DOCKER_HOST=tcp://127.0.0.1:4243
export PATH=/usr/local/bin:$PATH
BRANCH=${ref_name#refs/heads/}
REV=$new_rev
BASE_NAME=<%= app_name %>_$BRANCH
CONTAINER_NAME=$BASE_NAME:${REV:0:12}
DOCKER_REGISTRY_HOST=<%= docker_registry %>
RAILS_ENV=$BRANCH
LOG_TAG=$BRANCH

echo "-----> Fetching application source. base image=[<%= base_image %>]"

job=$(git archive --format=tar $new_rev | \
      sudo docker run -i -a stdin -e APP_NAME=<%= app_name%> <%= base_image %> \
      bash -c "mkdir -p /apps/<%= app_name %> && tar -C /apps/<%= app_name %> -xf -")
sudo docker logs -f $job
test $(sudo docker wait $job) -eq 0

echo "-----> (1/2)Create application container image ${job:0:8} -> [$CONTAINER_NAME]"
sudo docker commit $job $CONTAINER_NAME > /dev/null

echo "-----> Building new container ..."
job=$(sudo docker run -i -a stdin -e RAILS_ENV=$RAILS_ENV -e LOG_TAG=$LOG_TAG $CONTAINER_NAME \
     bash -c "cd /apps/<%= app_name %> && . /etc/profile.d/rbenv.sh &&
     bundle install -j4 --without test:development --path vendor/bundle --binstubs vendor/bundle/bin --deployment &&
     bower install --allow-root &&
     bundle exec rake tmp:create &&
     bundle exec rake assets:precompile")
sudo docker logs -f $job
test $(sudo docker wait $job) -eq 0

echo "-----> (2/2)Create application container image ${job:0:8} -> [$CONTAINER_NAME]"
sudo docker commit $job $CONTAINER_NAME > /dev/null
sudo docker tag $CONTAINER_NAME $BASE_NAME:latest
sudo docker tag $CONTAINER_NAME $DOCKER_REGISTRY_HOST/$CONTAINER_NAME

cat <<COMPLETE
Build complete!
See below creating tags.
  $CONTAINER_NAME
  $BASE_NAME:latest
  $DOCKER_REGISTRY_HOST/$CONTAINER_NAME
COMPLETE

echo "-----> Pushing new container to registry ..."
sudo docker push $DOCKER_REGISTRY_HOST/$CONTAINER_NAME
cat <<MESSAGE
Container pushed!
you can pull any server.
ex)
  sudo docker pull $DOCKER_REGISTRY_HOST/$CONTAINER_NAME
or
  sudo docker run $DOCKER_REGISTRY_HOST/$CONTAINER_NAME
MESSAGE

done
