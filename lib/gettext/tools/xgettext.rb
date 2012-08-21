# -*- coding: utf-8 -*-
#
# Copyright (C) 2012  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2012  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2003-2010  Masao Mutoh
# Copyright (C) 2001,2002  Yasushi Shoji, Masao Mutoh
#
# License: Ruby's or LGPL
#
# This library is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "pathname"
require "optparse"
require "gettext"

module GetText
  module Tools
    class XGetText #:nodoc:
      class << self
        def run(*arguments)
          new.run(*arguments)
        end
      end

      include GetText

      bindtextdomain("rgettext")

      def initialize #:nodoc:
        @ex_parsers = []
        parsers = [
          ["glade.rb", "GladeParser"],
          ["erb.rb", "ErbParser"],
          # ["ripper.rb", "RipperParser"],
          ["ruby.rb", "RubyParser"] # Default parser.
        ]
        parsers.each do |f, klass|
          begin
            require "gettext/tools/parser/#{f}"
            @ex_parsers << GetText.const_get(klass)
          rescue
            $stderr.puts(_("'%{klass}' is ignored.") % {:klass => klass})
            $stderr.puts($!) if $DEBUG
          end
        end

        @input_files = nil
        @output = nil

        @package_name = "PACKAGE"
        @package_version = "VERSION"
        @bugs_addr = ""
        @copyright = "THE PACKAGE'S COPYRIGHT HOLDER"
      end

      # How to add your option parser
      # The option parser module requires to have target?(file) and
      # parser(file, ary) method.
      #
      #  require "gettext/tools/xgettext"
      #  module FooParser
      #    module_function
      #    def target?(file)
      #      File.extname(file) == ".foo"  # *.foo file only.
      #    end
      #    def parse(file)
      #      :
      #      ary = []
      #      # Simple message
      #      po = PoMessage.new(:normal)
      #      po.msgid = "hello"
      #      po.sources = ["foo.rb:200", "bar.rb:300"]
      #      po.add_comment("Comment for the message")
      #      ary << po
      #      # Plural message
      #      po = PoMessage.new(:plural)
      #      po.msgid = "An apple"
      #      po.msgid_plural = "Apples"
      #      po.sources = ["foo.rb:200", "bar.rb:300"]
      #      ary << po
      #      # Simple message with the message context
      #      po = PoMessage.new(:msgctxt)
      #      po.msgctxt = "context"
      #      po.msgid = "hello"
      #      po.sources = ["foo.rb:200", "bar.rb:300"]
      #      ary << po
      #      # Plural message with the message context.
      #      po = PoMessage.new(:msgctxt_plural)
      #      po.msgctxt = "context"
      #      po.msgid = "An apple"
      #      po.msgid_plural = "Apples"
      #      po.sources = ["foo.rb:200", "bar.rb:300"]
      #      ary << po
      #      return ary
      #    end
      #  end
      #
      #  GetText::XGetText.add_parser(FooParser)
      def add_parser(klass)
        @ex_parsers.insert(0, klass)
      end

      def generate_pot_header # :nodoc:
        time = now.strftime("%Y-%m-%d %H:%M%z")

        <<EOH
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR #@copyright
# This file is distributed under the same license as the #@package_name package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: #@package_name #@package_version\\n"
"Report-Msgid-Bugs-To: #@bugs_addr\\n"
"POT-Creation-Date: #{time}\\n"
"PO-Revision-Date: #{time}\\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"
"Language-Team: LANGUAGE <LL@li.org>\\n"
"Language: \\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\\n"
EOH
      end

      def generate_pot(paths) # :nodoc:
        pomessages = parse(paths)
        str = ""
        pomessages.each do |target|
          str << target.to_po_str
        end
        str
      end

      def parse(paths) # :nodoc:
        pomessages = []
        paths = [paths] if paths.kind_of?(String)
        paths.each do |path|
          begin
            @ex_parsers.each do |klass|
              next unless klass.target?(path)

              if klass.method(:parse).arity == 1
                targets = klass.parse(path)
              else
                # For backward compatibility
                targets = klass.parse(path, [])
              end

              targets.each do |pomessage|
                if pomessage.kind_of?(Array)
                  pomessage = PoMessage.new_from_ary(pomessage)
                end

                if @output.is_a?(String)
                  base_path = Pathname.new(@output).dirname.expand_path
                  pomessage.sources = pomessage.sources.collect do |source|
                    path, line, = source.split(/:(\d+)\z/, 2)
                    absolute_path = Pathname.new(path).expand_path
                    begin
                      path = absolute_path.relative_path_from(base_path).to_s
                    rescue ArgumentError
                      raise # Should we ignore it?
                    end
                    "#{path}:#{line}"
                  end
                end

                # Save the previous target
                if pomessages.empty?
                  existing = nil
                else
                  message = pomessages.find {|t| t == pomessage}
                  existing = pomessages.index(message)
                end

                if existing
                  pomessage = pomessages[existing].merge(pomessage)
                  pomessages[existing] = pomessage
                else
                  pomessages << pomessage
                end
              end
              break
            end
          rescue
            puts(_("Error parsing %{path}") % {:path => path})
            raise
          end
        end
        pomessages
      end

      # constant values
      VERSION = GetText::VERSION

      def check_command_line_options(*options) # :nodoc:
        input_files, output = parse_arguments(*options)

        if input_files.empty?
          raise ArgumentError, _("no input files")
        end

        output ||= STDOUT

        @input_files = input_files
        @output = output
      end

      def parse_arguments(*options) #:nodoc:
        output = nil

        parser = OptionParser.new
        banner = _("Usage: %s input.rb [-r parser.rb] [-o output.pot]") % $0
        parser.banner = banner
        parser.separator("")
        description = _("Extract translatable strings from given input files.")
        parser.separator(description)
        parser.separator("")
        parser.separator(_("Specific options:"))

        parser.on("-o", "--output=FILE",
                  _("write output to specified file")) do |out|
          output = out
        end

        parser.on("-r", "--require=library",
                  _("require the library before executing xgettext")) do |out|
          require out
        end

        parser.on("-d", "--debug", _("run in debugging mode")) do
          $DEBUG = true
        end

        parser.on("-h", "--help", _("display this help and exit")) do
          puts(parser.help)
          exit(true)
        end

        parser.on("--package-name=PACKAGE",
                  _("set package name in output")) do |out|
          @package_name = out
        end

        parser.on("--package-version=VERSION",
                  _("set package version in output")) do |out|
          @package_version = out
        end

        parser.on("--msgid-bugs-address=EMAIL",
                  _("set report address for msgid bugs")) do |out|
          @bugs_addr = out
        end

        parser.on("--copyright-holder=STRING",
                  _("set copyright holder in output")) do |out|
          @copyright = out
        end

        parser.on_tail("--version", _("display version information and exit")) do
          puts(VERSION)
          exit(true)
        end

        parser.parse!(options)

        [options, output]
      end

      def run(*options)  # :nodoc:
        check_command_line_options(*options)

        if @output.is_a?(String)
          File.open(File.expand_path(@output), "w+") do |file|
            file.puts(generate_pot_header)
            file.puts(generate_pot(@input_files))
          end
        else
          @output.puts(generate_pot_header)
          @output.puts(generate_pot(@input_files))
        end
        self
      end

      private
      def now
        Time.now
      end
    end
  end
end