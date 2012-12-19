require 'spec_helper'

describe MB::Job do
  let(:type) { :provision }

  describe "ClassMethods" do
    subject { described_class }

    describe "::new" do
      subject { described_class.new(type) }

      before(:each) { subject }
      after(:each) { subject.terminate }

      it "starts in PENDING state" do
        subject.should be_pending
      end

      it "starts with a nil result" do
        subject.result.should be_nil
      end

      it "has a value for id" do
        subject.id.should_not be_nil
      end

      it "registers a job with JobManager" do
        MB::JobManager.instance.active.should have(1).item
        MB::JobManager.instance.active.should include(subject)
      end
    end
  end

  subject { described_class.new(type) }

  describe "#completed?" do
    it "should be completed if status is 'success'" do
      subject.transition(:running)
      subject.transition(:success)

      subject.should be_completed
    end

    it "should be completed if status is 'failure'" do
      subject.transition(:running)
      subject.transition(:failure)

      subject.should be_completed
    end

    it "should not be completed if status is 'pending'" do
      subject.should_not be_completed
    end

    it "should not be completed if status is 'running'" do
      subject.transition(:running)

      subject.should_not be_completed
    end
  end

  describe "#failure?" do
    it "should be a failure if status is 'failure'" do
      subject.transition(:running)
      subject.transition(:failure)

      subject.should be_failure
    end

    it "should not be a failure if status is not 'failure'" do
      subject.transition(:running)
      subject.transition(:success)

      subject.should_not be_failure
    end
  end

  describe "#pending?" do
    it "should be pending if status is 'pending'" do
      subject.should be_pending
    end

    it "should not be a pending if status is not 'pending'" do
      subject.transition(:running)

      subject.should_not be_pending
    end
  end

  describe "#running?" do
    it "should be running if status is 'running'" do
      subject.transition(:running)

      subject.should be_running
    end

    it "should not be running if status is not 'running'" do
      subject.transition(:running)
      subject.transition(:success)

      subject.should_not be_running
    end
  end

  describe "#success?" do
    it "should be a success if status is 'success'" do
      subject.transition(:running)
      subject.transition(:success)

      subject.should be_success
    end

    it "should not be success if status is not 'success'" do
      subject.transition(:running)
      subject.transition(:failure)

      subject.should_not be_success
    end
  end

  describe "#transition" do
    it "returns self" do
      result = subject.transition(:running)

      result.should eql(subject)
    end

    it "accepts and sets a result/reason" do
      subject.transition(:running, "a reason")

      subject.result.should eql("a reason")
      subject.should be_running
    end
  end
end