require 'rubygems'
require 'vagrant'
require 'vagrant-vbguest'

module Vagrant
  # This will handle proxying output from Vagrant into Jenkins
  class ConsoleInterface
    attr_accessor :listener, :resource

    def initializer(resource)
      @listener = nil
      @resource = resource
    end

    [:ask, :warn, :error, :info, :success].each do |method|
      define_method(method) do |message, *opts|
        @listener.info(message)
      end
    end

    [:clear_line, :report_progress].each do |method|
      # By default do nothing, these aren't logged
      define_method(method) do |*args|
      end
    end

    def ask(*args)
      super

      # Silent can't do this, obviously.
      raise Vagrant::Errors::UIExpectsTTY
    end
  end

  class BasicWrapper < Jenkins::Tasks::BuildWrapper
    display_name "Boot Vagrant box"

    attr_accessor :vagrantfile
    def initialize(attrs)
      @vagrant = nil
      @vagrantfile = attrs['vagrantfile']
    end

    # Called some time before the build is to start.
    def setup(build, launcher, listener)
      path = @vagrantfile.nil? ? build.workspace.to_s : @vagrantfile

      unless File.exists? File.join(path, 'Vagrantfile')
        listener.info("There is no Vagrantfile in your workspace!")
        listener.info("We looked in: #{path}")
        build.native.setResult(Java.hudson.model.Result::NOT_BUILT)
        build.halt
      end

      listener.info("Running Vagrant with version: #{Vagrant::VERSION}")
      @vagrant = Vagrant::Environment.new(:cwd => path, :ui_class => ConsoleInterface)
      @vagrant.ui.listener = listener

      listener.info "Vagrantfile loaded, bringing Vagrant box up for the build"
      @vagrant.cli('up', '--no-provision')
      listener.info "Vagrant box is online, continuing with the build"

      build.env[:vagrant] = @vagrant
      # We use this variable to determine if we have changes worth packaging,
      # i.e. if we have actually done anything with the box, we will mark it
      # dirty and can then take further action based on that
      build.env[:vagrant_dirty] = false
    end

    # Called some time when the build is finished.
    def teardown(build, listener)
      if @vagrant.nil?
        return
      end

      unless build.env[:vagrant_disable_destroy]
        listener.info "Build finished, destroying the Vagrant box"
        @vagrant.cli('destroy', '-f')
      end
    end
  end
end
