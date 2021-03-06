# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright (c) 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'java_buildpack/diagnostics'
require 'java_buildpack/diagnostics/common'
require 'logger'
require 'monitor'
require 'yaml'

module JavaBuildpack::Diagnostics

  class LoggerFactory
    # Create a Logger for the given application directory.
    #
    # @param [String] app_dir the root directory for diagnostics
    # @return [Logger] the created Logger instance
    def self.create_logger(app_dir)
      diagnostics_directory = JavaBuildpack::Diagnostics.get_diagnostic_directory app_dir
      FileUtils.mkdir_p diagnostics_directory
      log_file = File.join(diagnostics_directory, JavaBuildpack::Diagnostics::LOG_FILE_NAME)

      if (defined? @@logger) && (@@logger != nil)
        logger_recreated = true
        @@logger.warn("Logger is being re-created by #{caller[0]}")
      else
        logger_recreated = false
      end

      @@monitor.synchronize do
        @@logger = Logger.new(LogSplitter.new(File.open(log_file, 'a'), $stderr))
      end

      set_log_level

      @@logger.debug(log_file)
      if logger_recreated
        @@logger.warn("Logger was re-created by #{caller[0]}")
      end
      @@logger
    end

    # Gets the current logger instance.
    #
    # @return [Logger, nil] the current Logger instance or `nil` if there is no such instance
    def self.get_logger
      @@monitor.synchronize do
        @@logger
      end
    end

    private_class_method :new

    private

    DEBUG_SEVERITY_STRING = 'DEBUG'.freeze

    INFO_SEVERITY_STRING = 'INFO'.freeze

    WARN_SEVERITY_STRING = 'WARN'.freeze

    ERROR_SEVERITY_STRING = 'ERROR'.freeze

    FATAL_SEVERITY_STRING = 'FATAL'.freeze

    LOGGING_CONFIG = '../../../config/logging.yml'.freeze

    LOG_LEVEL_ENVIRONMENT_VARIABLE = 'JBP_LOG_LEVEL'.freeze

    DEFAULT_LOG_LEVEL_CONFIGURATION_KEY = 'default_log_level'.freeze

    @@monitor = Monitor.new

    def self.set_log_level
      logging_configuration = get_configuration
      switched_log_level = $VERBOSE || $DEBUG ? DEBUG_SEVERITY_STRING : nil
      log_level = (ENV[LOG_LEVEL_ENVIRONMENT_VARIABLE] || switched_log_level || logging_configuration[DEFAULT_LOG_LEVEL_CONFIGURATION_KEY]).upcase

      @@logger.sev_threshold = case
                               when log_level == DEBUG_SEVERITY_STRING then
                                 ::Logger::DEBUG
                               when log_level == INFO_SEVERITY_STRING then
                                 ::Logger::INFO
                               when log_level == WARN_SEVERITY_STRING then
                                 ::Logger::WARN
                               when log_level == ERROR_SEVERITY_STRING then
                                 ::Logger::ERROR
                               when log_level == FATAL_SEVERITY_STRING then
                                 ::Logger::FATAL
                               else
                                 ::Logger::DEBUG
                               end
    end

    def self.get_configuration
      expanded_path = File.expand_path(LOGGING_CONFIG, File.dirname(__FILE__))
      YAML.load_file(expanded_path)
    end

    def self.close
      @@monitor.synchronize do
        @@logger = nil
      end
    end

    class LogSplitter
      def initialize(*destinations)
        @destinations = destinations
      end

      def write(*args)
        @destinations.each do |destination|
          destination.write(*args)
          destination.flush
        end
      end

      def close
        @destinations.each do |destination|
          destination.close
        end
      end

    end

    class Logger < ::Logger
      def initialize(log_dev)
        super
      end

      def add(severity, message = nil, progname = nil, &block)

        if message || block_given?
          message_text = message
          program_name = progname
        else
          # progname is treated as a message if message is nil and the block is not given
          message_text = progname
          program_name = nil
        end
        # Skip stack frames in file 'logger.rb'.
        # Note: there is no way to detect the class ::Logger since caller does not include the class name and
        # the class may be reopened in arbitrary files.
        program_name ||= caller.find { |stack_frame| !(stack_frame =~ /logger\.rb/) }
        super(severity, message_text, program_name, &block)
      end

      def close
        warn(caller[0]) { 'logger is being closed' }
        super
        LoggerFactory.close
      end

    end

  end

end
