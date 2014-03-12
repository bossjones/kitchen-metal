# -*- encoding: utf-8 -*-
#
# Author:: Douglas Triggs (<doug@getchef.com>), John Keiser (<jkeiser@getchef.com>)
#
# Copyright (C) 2014, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'chef/node'
require 'chef/run_context'
require 'chef/event_dispatch/dispatcher'
require 'chef/recipe'
require 'chef/runner'
require 'chef/formatters/doc'

require 'chef_metal'
require 'chef/providers'
require 'chef/resources'

module Kitchen
  module Driver

    # Metal driver for Kitchen. Using Metal recipes for great justice.
    #
    # @author Douglas Triggs <doug@getchef.com>
    #
    # This structure is based on (read: shamelessly stolen from) the generic kitchen
    # vagrant driver written by Fletcher Nichol and modified for our nefarious
    # purposes.

    class Metal < Kitchen::Driver::Base
      default_config :transport, :ssh

      def create(state)
        run_pre_create_command
        run_recipe(state)
        info("Vagrant instance #{instance.to_str} created.")
      end

      def converge(state)
        run_recipe(state)
#        provisioner = instance.provisioner
#        provisioner.create_sandbox
#        sandbox_dirs = Dir.glob("#{provisioner.sandbox_path}/*")

#        Kitchen::SSH.new(*build_ssh_args(state)) do |conn|
#          run_remote(provisioner.install_command, conn)
#          run_remote(provisioner.init_command, conn)
#          transfer_path(sandbox_dirs, provisioner[:root_path], conn)
#          run_remote(provisioner.prepare_command, conn)
#          run_remote(provisioner.run_command, conn)
#        end
#      ensure
#        provisioner && provisioner.cleanup_sandbox
      end

      def setup(state)
        run_recipe(state)
#        Kitchen::SSH.new(*build_ssh_args(state)) do |conn|
#          run_remote(busser_setup_cmd, conn)
#        end
      end

      def verify(state)
        run_recipe(state)
#        Kitchen::SSH.new(*build_ssh_args(state)) do |conn|
#          run_remote(busser_sync_cmd, conn)
#          run_remote(busser_run_cmd, conn)
#        end
      end

      def destroy(state)
        run_destroy(state)
        info("Vagrant instance #{instance.to_str} destroyed.")
      end

#      def login_command(state)
#        SSH.new(*build_ssh_args(state)).login_command
#      end

#      def ssh(ssh_args, command)
#        Kitchen::SSH.new(*ssh_args) do |conn|
#          run_remote(command, conn)
#        end
#      end

      protected

      def get_driver_recipe
        return nil if config[:layout].nil?
        path = "#{config[:kitchen_root]}/#{config[:layout]}"
        file = File.open(path, "rb")
        contents = file.read
        file.close
        contents
      end

      def get_platform_recipe
        path = "#{config[:kitchen_root]}/#{instance.platform.name}"
        file = File.open(path, "rb")
        contents = file.read
        file.close
        contents
      end

      def run_recipe(state)
        return if @environment_created
        node = Chef::Node.new
        node.name 'nothing'
        node.automatic[:platform] = 'kitchen_metal'
        node.automatic[:platform_version] = 'kitchen_metal'
        Chef::Config.local_mode = true
        run_context = Chef::RunContext.new(node, {},
          Chef::EventDispatch::Dispatcher.new(Chef::Formatters::Doc.new(STDOUT,STDERR)))
        recipe_exec = Chef::Recipe.new('kitchen_vagrant_metal',
          'kitchen_vagrant_metal', run_context)
        # We require a platform, but layout in driver is optional
        recipe = get_driver_recipe
        recipe_exec.instance_eval recipe if recipe
        recipe_exec.instance_eval get_platform_recipe
        Chef::Runner.new(run_context).converge
        machines = []
        run_context.resource_collection.each do |resource|
          if (resource.is_a?(Chef::Resource::Machine))
            if (!machines.include?(resource.name))
              machines.push(resource.name)
            end
          end
        end
        state[:machines] = machines
        @environment_created = true
      end

      def run_destroy(state)
        return if !@environment_created || !state[:machines] || state[:machines].size == 0
        machines = state[:machines]
        chef_server = Cheffish::CheffishServerAPI.new(Cheffish.enclosing_chef_server)
        nodes = chef_server.get("/nodes")
        nodes.each_key do |key|
          if (machines.include?(key))
            node_url = nodes[key]
            node = chef_server.get(node_url)
            node_url = node['normal']['provisioner_output']['provisioner_url']
            cluster_type = node_url.gsub(/\:\/\/.*$/,"")
            cluster_path = node_url.gsub(/^.*\:\/\//,"")
            # TODO: Temporary hard-coded provisioner for the moment; in the future,
            # need to add registry in metal
            # TODO: Can we get around special cases for new params?
            provisioner = ChefMetal::Provisioner::VagrantProvisioner.new(cluster_path)
            provisioner.delete_machine(KitchenActionHandler.new("test_kitchen"), node)
          end
        end
        state[:machines] = []
        @environment_created = false
      end

#      def build_ssh_args(state)
#        combined = config.to_hash.merge(state)

#        opts = Hash.new
#        opts[:user_known_hosts_file] = "/dev/null"
#        opts[:paranoid] = false
#        opts[:keys_only] = true if combined[:ssh_key]
#        opts[:password] = combined[:password] if combined[:password]
#        opts[:forward_agent] = combined[:forward_agent] if combined.key? :forward_agent
#        opts[:port] = combined[:port] if combined[:port]
#        opts[:keys] = Array(combined[:ssh_key]) if combined[:ssh_key]
#        opts[:logger] = logger

#        [combined[:hostname], combined[:username], opts]
#      end

#      def env_cmd(cmd)
#        env = "env"
#        env << " http_proxy=#{config[:http_proxy]}"   if config[:http_proxy]
#        env << " https_proxy=#{config[:https_proxy]}" if config[:https_proxy]

#        env == "env" ? cmd : "#{env} #{cmd}"
#      end

#      def run_remote(command, connection)
#        return if command.nil?

#        connection.exec(env_cmd(command))
#      rescue SSHFailed, Net::SSH::Exception => ex
#        raise ActionFailed, ex.message
#      end

#      def transfer_path(locals, remote, connection)
#        return if locals.nil? || Array(locals).empty?

#        info("Transferring files to #{instance.to_str}")
#        locals.each { |local| connection.upload_path!(local, remote) }
#        debug("Transfer complete")
#      rescue SSHFailed, Net::SSH::Exception => ex
#        raise ActionFailed, ex.message
#      end

#      def wait_for_sshd(hostname, username = nil, options = {})
#        SSH.new(hostname, username, { :logger => logger }.merge(options)).wait
#      end

      def run(cmd, options = {})
        cmd = "echo #{cmd}" if config[:dry_run]
        run_command(cmd, { :cwd => config[:kitchen_root] }.merge(options))
      end

      def run_pre_create_command
        if config[:pre_create_command]
          run(config[:pre_create_command], :cwd => config[:kitchen_root])
        end
      end
    end
  end
end
