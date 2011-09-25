#require 'digest/md5'
#require 'fpm/cookery/recipe_inspector'
#require 'fpm/cookery/dependency_inspector'
require 'fpm/cookery/utils'

module FPM
  module Cookery
    class Packager
      include FPM::Cookery::Utils

      attr_reader :recipe, :config

      def initialize(recipe, config = {})
        @recipe = recipe
        @config = config
      end

      def cleanup
        FileUtils.rm_rf(recipe.builddir)
        FileUtils.rm_rf(recipe.destdir)
      end

      def dispense
        env = ENV.to_hash

        # RecipeInspector.verify!(recipe)
        # DependencyInspector.verify!(recipe.depends, recipe.build_depends)

        recipe.installing = false

        source = recipe.source

        recipe.cachedir.mkdir
        Dir.chdir(recipe.cachedir) do
          source.fetch

          #check = Source::IntegrityCheck.new(source.filename, recipe.md5, Digest::MD5)

          #if check.error?
            # check.actual, check.expected, check.filename, check.digest
          #end
        end

        recipe.builddir.mkdir
        Dir.chdir(recipe.builddir) do
          extracted_source = source.extract

          Dir.chdir(extracted_source) do
            #Source::Patches.new(recipe.patches).apply!

            build_cookie = build_cookie_name("#{recipe.name}-#{recipe.version}")

            if File.exists?(build_cookie)
              STDERR.puts 'Skipping build (`cook clean` to rebuild)'
            else
              recipe.build and FileUtils.touch(build_cookie)
            end

            FileUtils.rm_rf(recipe.destdir)
            recipe.destdir.mkdir

            begin
              recipe.installing = true
              recipe.install
            ensure
              recipe.installing = false
            end
          end
        end

        build_package(recipe, config)
      ensure
        # Make sure we reset the environment.
        ENV.replace(env)
      end

      def build_cookie_name(name)
        (recipe.builddir/".build-cookie-#{name.gsub(/[^\w]/,'_')}").to_s
      end

      def build_package(recipe, config)
        recipe.pkgdir.mkdir
        Dir.chdir(recipe.pkgdir) do
          epoch, ver = recipe.version.split(':', 2)
          if ver.nil?
            ver, epoch = epoch, nil
          end

          # Build a version including vendor and revision.
          vendor = config[:vendor] || recipe.vendor
          vendor_rev = "#{vendor}#{recipe.revision}"
          version = [ver, vendor_rev].join('+')

          maintainer = recipe.maintainer || begin
            username = `git config --get user.name`.strip
            useremail = `git config --get user.email`.strip
            raise 'Set maintainer name/email via `git config --global user.name <name>`' if username.empty?
            "#{username} <#{useremail}>"
          end

          opts = [
            '-n', recipe.name,
            '-v', version,
            '-t', 'deb',
            '-s', 'dir',
            '--url', recipe.homepage || recipe.url,
            '-C', recipe.destdir,
            '--maintainer', maintainer,
            '--category', recipe.section || 'optional',
          ]

          opts += [
            '--epoch', epoch
          ] if epoch

          opts += [
            '--description', recipe.description.strip
          ] if recipe.description

          opts += [
            '--architecture', recipe.arch.to_s
          ] if recipe.arch

#          if self.postinst
#            postinst_file = Tempfile.open('postinst')
#            postinst_file.puts(postinst)
#            chmod 0755, postinst_file.path
#            postinst_file.close
#            opts += ['--post-install', postinst_file.path]
#          end
#          if self.postrm
#            postrm_file = Tempfile.open('postrm')
#            postrm_file.puts(postrm)
#            chmod 0755, postrm_file.path
#            postrm_file.close
#            opts += ['--post-uninstall', postrm_file.path]
#          end

          %w[ depends provides replaces conflicts config_files ].each do |type|
            if recipe.send(type).any?
              recipe.send(type).each do |dep|
                opts += ["--#{type.gsub('_','-')}", dep]
              end
            end
          end

          opts << '.'

          STDERR.puts ['fpm', opts].flatten.inspect
          safesystem(*['fpm', opts].flatten)
        end
      end
    end
  end
end