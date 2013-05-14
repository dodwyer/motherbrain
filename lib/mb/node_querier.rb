require 'net/sftp'

module MotherBrain
  # @author Jamie Winsor <reset@riotgames.com>
  class NodeQuerier
    class << self
      # @raise [Celluloid::DeadActorError] if Node Querier has not been started
      #
      # @return [Celluloid::Actor(NodeQuerier)]
      def instance
        MB::Application[:node_querier] or raise Celluloid::DeadActorError, "node querier not running"
      end
    end

    extend Forwardable
    include Celluloid
    include MB::Logging
    include MB::Mixin::Services

    finalizer do
      log.info { "Node Querier stopping..." }
    end

    def initialize
      log.info { "Node Querier starting..." }
    end

    # List all of the nodes on the target Chef Server
    #
    # @return [Array<Hash>]
    def list
      chef_connection.node.all
    end

    # Run Chef on a group of nodes, and update a job status with the result
    # @param [Job] job
    # @param [Array(Ridley::NodeResource)] nodes
    #   The collection of nodes to run Chef on
    #
    # @raise [RemoteCommandError]
    def bulk_chef_run(job, nodes)
      job.set_status("Performing a chef client run on #{nodes.collect(&:name).join(', ')}")

      node_successes = 0
      node_failures = 0

      futures = nodes.map { |node|
        node_querier.future.chef_run(node.public_hostname)
      }

      futures.each do |future|
        begin
          future.value
          node_successes += 1
        rescue RemoteCommandError
          node_failures += 1
        end
      end

      if node_failures > 0
        abort RemoteCommandError.new("chef client run failed on #{node_failures} node(s)")
      else
        job.set_status("Finished chef client run on #{node_successes} node(s)")
      end
    end

    # Return the Chef node_name of the target host. A nil value is returned if a
    # node_name cannot be determined
    #
    # @param [String] host
    #   hostname of the target node
    # @option options [String] :user
    #   a shell user that will login to each node and perform the bootstrap command on (required)
    # @option options [String] :password
    #   the password for the shell user that will perform the bootstrap
    # @option options [Array, String] :keys
    #   an array of keys (or a single key) to authenticate the ssh user with instead of a password
    # @option options [Float] :timeout (10.0)
    #   timeout value for SSH bootstrap
    # @option options [Boolean] :sudo (true)
    #   bootstrap with sudo
    #
    # @return [String, nil]
    def node_name(host, options = {})
      ruby_script('node_name', host, options)
    rescue MB::RemoteScriptError
      nil
    end

    # Run Chef-Client on the target host
    #
    # @param [String] host
    #
    # @option options [String] :user
    #   a shell user that will login to each node and perform the bootstrap command on (required)
    # @option options [String] :password
    #   the password for the shell user that will perform the bootstrap
    # @option options [Array, String] :keys
    #   an array of keys (or a single key) to authenticate the ssh user with instead of a password
    # @option options [Float] :timeout (10.0)
    #   timeout value for SSH bootstrap
    # @option options [Boolean] :sudo
    #   bootstrap with sudo
    #
    # @raise [RemoteCommandError] if an execution error occurs in the remote command
    # @raise [RemoteCommandError] if given a blank or nil hostname
    #
    # @return [Ridley::HostConnector::Response]
    def chef_run(host, options = {})
      options = options.dup

      unless host.present?
        abort RemoteCommandError.new("cannot execute a chef-run without a hostname or ipaddress")
      end

      log.info { "Running Chef client on: #{host}" }

      status, response = chef_connection.node.chef_run(host)

      case status
      when :ok
        log.info { "Completed Chef client run on: #{host}" }
        response
      when :error
        log.info { "Failed Chef client run on: #{host}" }
        abort RemoteCommandError.new(response.stderr.chomp)
      end
    end

    # Place an encrypted data bag secret on the target host
    #
    # @param [String] host
    #
    # @option options [String] :secret
    #   the encrypted data bag secret of the node querier's chef conn will be used
    #   as the default key
    # @option options [String] :user
    #   a shell user that will login to each node and perform the bootstrap command on (required)
    # @option options [String] :password
    #   the password for the shell user that will perform the bootstrap
    # @option options [Array, String] :keys
    #   an array of keys (or a single key) to authenticate the ssh user with instead of a password
    # @option options [Float] :timeout (10.0)
    #   timeout value for SSH bootstrap
    # @option options [Boolean] :sudo
    #   bootstrap with sudo
    #
    # @raise [RemoteFileCopyError]
    #
    # @return [Ridley::HostConnector::Response]
    def put_secret(host, options = {})
      options = options.reverse_merge(
        secret: Application.config.chef.encrypted_data_bag_secret_path
      )

      if options[:secret].nil? || !File.exists?(options[:secret])
        return nil
      end

      status, response = chef_connection.node.put_secret(host)

      case status
      when :ok
        log.info { "Successfully put secret file on: #{host}" }
        response
      when :error
        log.info { "Failed to put secret file on: #{host}" }
        nil
      end
    end

    # Executes the given command on the host using the best worker
    # available for the host.
    #
    # @param [String] host
    # @param [String] command
    #
    # @return [Ridley::HostConnection::Response]
    def execute_command(host, command)
      status, response = chef_connection.node.execute_command(host, command)

      case status
      when :ok
        log.info { "Successfully executed command on: #{host}" }
        response
      when :error
        log.info { "Failed to execute command on: #{host}" }
        abort RemoteCommandError.new(response.stderr.chomp)
      end
    end

    # Check if the target host is registered with the Chef server. If the node does not have Chef and
    # ruby installed by omnibus it will be considered unregistered.
    #
    # @example showing a node who is registered to Chef
    #   node_querier.registered?("192.168.1.101") #=> true
    # @example showing a node who does not have ruby or is not registered to Chef
    #   node_querier.registered?("192.168.1.102") #=> false
    #
    # @param [String] host
    #   public hostname of the target node
    #
    # @return [Boolean]
    def registered?(host)
      !!registered_as(host)
    end

    # Returns the client name the target node is registered to Chef with.
    #
    # If the node does not have a client registered with the Chef server or if Chef and ruby were not installed
    # by omnibus this function will return nil.
    #
    # @example showing a node who is registered to Chef
    #   node_querier.registered_as("192.168.1.101") #=> "reset.riotgames.com"
    # @example showing a node who does not have ruby or is not registered to Chef
    #   node_querier.registered_as("192.168.1.102") #=> nil
    #
    # @param [String] host
    #   public hostname of the target node
    #
    # @return [String, nil]
    def registered_as(host)
      if (client_id = node_name(host)).nil?
        return nil
      end

      chef_connection.client.find(client_id).try(:name)
    end

    private

      # Run a Ruby script on the target host and return the result of STDOUT. Only scripts
      # that are located in the Mother Brain scripts directory can be used and they should
      # be identified just by their filename minus the extension
      #
      # @example
      #   node_querier.ruby_script('node_name', '33.33.33.10') => 'vagrant.localhost'
      #
      # @param [String] name
      #   name of the script to run on the target node
      # @param [String] host
      #   hostname of the target node
      #   the MotherBrain scripts directory
      # @option options [String] :user
      #   a shell user that will login to each node and perform the bootstrap command on (required)
      # @option options [String] :password
      #   the password for the shell user that will perform the bootstrap
      # @option options [Array, String] :keys
      #   an array of keys (or a single key) to authenticate the ssh user with instead of a password
      # @option options [Float] :timeout (10.0)
      #   timeout value for SSH bootstrap
      # @option options [Boolean] :sudo (true)
      #   bootstrap with sudo
      #
      # @raise [RemoteScriptError] if there was an error in execution
      # @raise [RuntimeError] if an unknown response is returned from Ridley
      #
      # @note
      #   Use {#_ruby_script_} if the caller of this function is same actor as the receiver. You will
      #   not be able to rescue from the RemoteScriptError thrown by {#ruby_script} but you will
      #   be able to rescue from {#_ruby_script_}.
      #
      # @return [String]
      def ruby_script(name, host, options = {})
        name    = name.split('.rb')[0]
        lines   = File.readlines(MB.scripts.join("#{name}.rb"))
        command_lines = lines.collect { |line| line.gsub('"', "'").strip.chomp }

        status, response = chef_connection.node.ruby_script(host, command_lines)

        case status
        when :ok
          response.stdout.chomp
        when :error
          raise RemoteScriptError.new(response.stderr.chomp)
        else
          raise RuntimeError, "unknown status returned from #ruby_script: #{status}"
        end
      end
  end
end
