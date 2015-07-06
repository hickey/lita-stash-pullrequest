require 'uri'
require 'net/http'
require 'json'

require_relative '../../subscriptions'


module Lita
  module Handlers
    class StashPullrequest < Handler
      
      def initialize(robot)
        super(robot)
        @subscriptions = Subscription.new
        @token = (robot.adapters[:slack].config.select {|c| c.value if c.name == :token})[0].value
      end
      
    
      http.post '/stash-pullrequest', :process_pullrequest
    
      route /^pr\s+repos?\s+list/, :repo_list, 
            help: {'pr repo list' => 'List the repos that can be subscribed to'}
      
      route /^pr\s+sub(?:scribe)?\s+(?<repo>.*)/, :repo_subscribe,
            help: {'pr sub[scribe] REPO' => 'Subscribe to the given repository'}
      
      route /^pr\s+ch(?:annel)?\s+sub(?:scribe)?\s+(?<repo>.*)/, :repo_subscribe,
            help: {'pr ch[annel] sub[scribe] REPO' => 'Subscribe the current channel to the given repository'}
                  
      route /^pr\s+unsub(?:scribe)?\s+(?<repo>.*)/, :repo_unsubscribe,
            help: {'pr unsub[scribe] REPO' => 'Unsubscribe to the given repository'}
      
      route /^pr\s+ch(?:annel)?\s+unsub(?:scribe)?\s+(?<repo>.*)/, :repo_unsubscribe,
            help: {'pr ch[annel] unsub[scribe] REPO' => 'Unsubscribe the current channel to the given repository'}
                  
      route /^pr\s+list\+sub(?:scriptions)?\s*(?<repo>.*)/, :repo_list_subscriptions,
            help: {'pr list sub[scriptions] REPO' => 'Subcription list'}
      
      route /^pr\s+info/, :repo_info
    
      def repo_list(response)
        reply_text = "Available repositories\n```"
        reply_text << @subscriptions.all.sort.join("\n")
        reply_text << '```'
        
        response.reply reply_text
      end
      
      
      def repo_list_subscriptions(response)
        reply_text = "You are subscribed for pull requests from the following repositories:\n```"
        
        @subscriptions.all.each do |repo|
          if @subscriptions.members(repo).include? @user.id
            reply_text << "#{repo}\n"
          end
        end
        
        reply_text << "```\n"
        response.reply reply_text
      end
      
      
      def repo_subscribe(response)
        if response.pattern.to_s.include? 'ch'
          contact = '#' + response.message.source.room
        else
          contact = '@' + response.user.id
        end
        
        repo = response.matches.first[0]
        if @subscriptions.all.include? repo
          @subscriptions.enroll repo, contact
          response.reply "You are now subscribed to receive pull request notification for #{repo}"
        else
          response.reply "Unable to find a repository named #{repo}"
        end
      end
    
    
      def repo_unsubscribe(response)
        if response.pattern.to_s.include? 'ch'
          contact = '#' + response.message.source.room
        else
          contact = '@' + response.user.id
        end
        
        repo = response.matches.first[0]
        if @subscriptions.all.include? repo
          @subscriptions.cancel repo, contact
          response.reply "You are now unsubscribed to receive pull request notification for #{repo}"
        else
          response.reply "Unable to find a repository named #{repo}"
        end
      end
      
      
      def repo_info(response)
        puts "=============================="
        puts "response = #{response.inspect}"
        puts "=============================="

        puts response.matches.inspect

        puts "=============================="
        puts "robot = #{@robot.inspect}"
        puts "=============================="
        puts "robot methods = #{@robot.methods}"
        puts "robot.adapters = #{@robot.adapters}"
        puts "robot.handlers = #{@robot.handlers.inspect}"
        puts "robot.hooks = #{@robot.hooks}"
        puts "=============================="
        puts "robot vars = #{@robot.instance_variables}"
        puts "robot.registry = #{@robot.registry}"
        puts "robot.name = #{@robot.name}"
        puts "robot.mention_name = #{@robot.mention_name}"
        puts "robot.alias = #{@robot.alias}"
        puts "robot.app = #{@robot.app}"
        puts "robot.auth = #{@robot.auth}"
        puts "=============================="
        puts "adapter = #{@robot.adapters[:slack].inspect}"
        puts "adapter.instance_methods = #{@robot.adapters[:slack].instance_methods}"
        puts "=============================="
        puts "adapter methods = #{@robot.adapters[:slack].methods}"
        puts "=============================="
        puts "adapter vars = #{@robot.adapters[:slack].instance_variables}"
        puts "adapter.configuration_builder = #{@robot.adapters[:slack].configuration_builder}"
        puts "=============================="
        puts "adapter conf = #{@robot.adapters[:slack].config.inspect}"
        #Lita::Adapters::Slack::API.new(config).call_api('chat.postMessage', {:channel => @room, :username => 'gort',
#               :text => 'testing' })
        post_message_to(response.message.source.room, 'testing')
      end
    
    
      def process_pullrequest(request, response)
        data = parse(request.body.read)
        repo_key = "#{data[:to_project_key]}/#{data[:to_repo_slug]}"
        Lita.logger.info "Received PR webhook for #{repo_key}"
        
        unless @subscriptions.repo? repo_key
          @subscriptions.enroll(repo_key, '')
        end
        
        # do we have a pull request to report on?
        @subscriptions.members(repo_key).each do |userid|
          # create a contact handle to use to send message to
          if userid.start_with? '@'
            contact_handle = Lita::Source.new(user: 
                        Lita::User.find_by_id(userid.delete('@')))
            contact = contact_handle.user.metadata['mention_name']
          elsif userid.start_with? '#'
            contact_handle = Lita::Source.new(room: userid.delete('#'))
            contact = userid
          end

          Lita.logger.info "Attempting to notify #{contact} about #{data[:action]}"

          case data[:action]
          when 'OPENED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} *created* against #{data[:from_branch]}")
          when 'REOPENED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} has been *reopened* by #{data[:author_display_name]}")
          when 'MERGED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} *merged* to #{data[:to_branch]}")
          when 'DECLINED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} *declined* by #{data[:author_display_name]}")
          when 'APPROVED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} *approved* by #{data[:author_display_name]}")
          when 'UNAPPROVED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} *unapproved* by #{data[:author_display_name]}")
          when 'UPDATED'
            @robot.send_message(contact_handle, 
                  "#{repo_key} PR ##{data[:id]} has been *updated*")
          end
        end
      end
      
      
      def post_message_to(user, mesg)
        uri = URI('https://slack.com/api/chat.postMessage')
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        
        request = Net::HTTP::Post.new(uri.path)
        request.body = {'token' => @token, 'channel' => user,
                        'text' => mesg, 'link_names' => 1, }.to_json
        response = https.request(request)
      end
      
      
      def receive(request, response)
        I18n.locale = Lita.config.robot.locale

        room = request.params['room']
        target = Source.new(room: room)
        data = parse(request.body.read)
        message = format(data)
        return if message.nil?
        robot.send_message(target, message)
      end

      private

      def parse(json)
        MultiJson.load(json, symbolize_keys: true)
      rescue MultiJson::ParseError => exception
        exception.data
        exception.cause
      end

    end

    Lita.register_handler(StashPullrequest)
  end
end
