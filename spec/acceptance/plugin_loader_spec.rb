require 'spec_helper'

describe "loading a plugin" do
  let(:dsl_content) do
    <<-EOH
      name "pvpnet"
      version "1.2.3"
      description "whatever"
      author "Jamie Winsor"
      email "jamie@vialstudios.com"

      # depends "pvpnet", "~> 1.2.3"
      # depends "activemq", "= 4.2.1"

      command :start do
        component(:activemq).invoke(:start)
      end

      component :activemq do
        group :master_broker do
          recipe "activemq::broker"
          role "why_man_why"
          attribute 'activemq.broker.master', true
        end

        # service :broker do
        #   action :start do
        #     set_attribute('activemq.broker.status', true)
        #   end

        #   action :stop do
        #     set_attribute('activemq.broker.status', false)
        #   end
        # end

        # command :start do
        #   run do
        #     service(:broker, :start).on(:master_broker)
        #   end
        # end

        # command :stop do
        #   run.service(:broker, :stop).on(:master_broker)
        # end
      end
    EOH
  end

  before(:each) { @plugin = MB::Plugin.load(dsl_content) }
  subject { @plugin }

  it { subject.name.should eql("pvpnet") }
  it { subject.version.should eql("1.2.3") }
  it { subject.description.should eql("whatever") }
  it { subject.author.should eql("Jamie Winsor") }
  it { subject.email.should eql("jamie@vialstudios.com") }

  it { subject.components.should have(1).item }
  it { subject.component(:activemq).should_not be_nil }

  it { subject.commands.should have(1).item }
  it { subject.command(:start).should_not be_nil }

  describe "component" do
    subject { @plugin.component(:activemq) }

    it { subject.groups.should have(1).item }
    it { subject.group(:master_broker).should_not be_nil }

    describe "group" do
      subject { @plugin.component(:activemq).group(:master_broker) }

      it { subject.recipes.should have(1).item }
      it { subject.recipes.should include("activemq::broker") }

      it { subject.roles.should have(1).item }
      it { subject.roles.should include("why_man_why") }

      it { subject.attributes.should have(1).item }
      it { subject.attributes.should include("activemq.broker.master" => true) }
    end
  end

  describe "commands" do
    subject { @plugin.commands }

    it { subject[0].should be_a(Proc) }
  end
end