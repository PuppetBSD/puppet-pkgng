#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet/provider/package/pkgng'

provider_class = Puppet::Type.type(:package).provider(:pkgng)

describe provider_class do
  let(:name) { 'bash' }
  let(:pkgng) { 'pkgng' }

  let(:resource) do
    # When bash is not present
    Puppet::Type.type(:package).new(:name => name, :provider => pkgng)
  end

  let(:installed_resource) do
    # When zsh is present
    Puppet::Type.type(:package).new(:name => 'zsh', :provider => pkgng)
  end

  let(:latest_resource) do
    # When curl is installed but not the latest
    Puppet::Type.type(:package).new(:name => 'ftp/curl', :provider => pkgng, :ensure => latest)
  end

  let (:provider) { resource.provider }

  def run_in_catalog(*resources)
    catalog = Puppet::Resource::Catalog.new
    catalog.host_config = false
    resources.each do |resource|
      #resource.expects(:err).never
      catalog.add_resource(resource)
    end
    catalog.apply
  end

  before do
    allow(provider_class).to receive(:command).with(:pkg) { '/usr/local/sbin/pkg' }

    info = File.read('spec/fixtures/pkg.info')
    allow(provider_class).to receive(:get_query) { info }

    version_list = File.read('spec/fixtures/pkg.version')
    allow(provider_class).to receive(:get_version_list) { version_list }
  end

  context "#instances" do
    it "should return the empty set if no packages are listed" do
      allow(provider_class).to receive(:get_query) { '' }
      allow(provider_class).to receive(:get_version_list) { '' }
      expect(provider_class.instances).to be_empty
    end

    it "should return all packages when invoked" do
      expect(provider_class.instances.map(&:name).sort).to eq(
        %w{ca_root_nss curl nmap pkg gnupg mcollective zsh tac_plus}.sort)
    end

    it "should set latest to current version when no upgrade available" do
      nmap = provider_class.instances.find {|i| i.properties[:origin] == 'security/nmap' }

      expect(nmap.properties[:version]).to eq(nmap.properties[:latest])
    end

    describe "version" do
      it "should retrieve the correct version of the current package" do
        zsh = provider_class.instances.find {|i| i.properties[:origin] == 'shells/zsh' }
        expect(zsh.properties[:version]).to eq('5.0.2_1')
      end
    end
  end

  context "#install" do
    it "should call pkg with the specified package version given an origin for package name" do
      resource = Puppet::Type.type(:package).new(
        :name     => 'ftp/curl',
        :provider => :pkgng,
        :ensure   => '7.33.1'
      )
      allow(resource.provider).to receive(:pkg) do |arg|
        expect(arg).to include('curl-7.33.1')
      end
      resource.provider.install
    end

    it "should call pkg with the specified package version" do
      resource = Puppet::Type.type(:package).new(
        :name     => 'curl',
        :provider => :pkgng,
        :ensure   => '7.33.1'
      )
      allow(resource.provider).to receive(:pkg) do |arg|
        expect(arg).to include('curl-7.33.1')
      end
      resource.provider.install
    end

    it "should call pkg with the specified package repo" do
      resource = Puppet::Type.type(:package).new(
        :name     => 'curl',
        :provider => :pkgng,
        :source   => 'urn:freebsd:repo:FreeBSD'
      )
      allow(resource.provider).to receive(:pkg) do |arg|
        expect(arg).to include('FreeBSD')
      end
      resource.provider.install
    end
  end

  context "#query" do
    # This is being commented out as I am not sure how to test the code when
    # using prefetching.  I somehow need to pass a fake resources object into
    # #prefetch so that it can build the @property_hash, but I am not sure how.
    #
    #it "should return the installed version if present" do
    #  fixture = File.read('spec/fixtures/pkg.query')
    #  provider_class.stub(:get_resource_info) { fixture }
    #  resource[:name] = 'zsh'
    #  expect(provider.query).to eq({:version=>'5.0.2'})
    #end

    it "should return nil if not present" do
      fixture = File.read('spec/fixtures/pkg.query_absent')
      allow(provider_class).to receive(:get_resource_info).with('bash') { fixture }
      expect(provider.query).to equal(nil)
    end
  end

  describe "latest" do
    it "should retrieve the correct version of the latest package" do
      expect(provider.latest).to eq(nil)
    end

    it "should set latest to newer package version when available" do
      instances = provider_class.instances
      curl = instances.find {|i| i.properties[:origin] == 'ftp/curl' }
      expect(curl.properties[:latest]).to eq("7.33.0_2")
    end

    it "should call update to upgrade the version" do
      resource = Puppet::Type.type(:package).new(
        :name     => 'ftp/curl',
        :provider => pkgng,
        :ensure   => :latest
      )

      expect(resource.provider).to receive(:update)

      resource.property(:ensure).sync
    end
  end

  describe "get_latest_version" do
    it "should rereturn nil when the current package is the latest" do
      nmap_latest_version = provider_class.get_latest_version('security/nmap')
      expect(nmap_latest_version).to be_nil
    end

    it "should match the package name exactly" do
      bash_comp_latest_version = provider_class.get_latest_version('shells/bash-completion')
      expect(bash_comp_latest_version).to eq("2.1_3")

      bash_latest_version = provider_class.get_latest_version('shells/bash')
      expect(bash_latest_version).to be_nil
    end
  end
end
