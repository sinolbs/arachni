require 'spec_helper'

describe Arachni::BrowserCluster::Worker do
    before( :each ) do
        @cluster = Arachni::BrowserCluster.new( pool_size: 1 )
    end
    after( :each ) do
        @cluster.shutdown if @cluster
        @worker.shutdown  if @worker
    end

    let(:url) { Arachni::Utilities.normalize_url( web_server_url_for( :browser ) ) }
    let(:job) do
        Arachni::BrowserCluster::Jobs::ResourceExploration.new(
            resource: Arachni::HTTP::Client.get( url + 'explore', mode: :sync )
        )
    end
    let(:custom_job) { Factory[:custom_job] }
    let(:sleep_job) { Factory[:sleep_job] }
    let(:subject) { @cluster.workers.first }

    describe '#initialize' do
        describe :job_timeout do
            it 'sets how much time to allow each job to run' do
                @worker = described_class.new( job_timeout: 10 )
                @worker.job_timeout.should == 10
            end

            it "defaults to #{Arachni::OptionGroups::BrowserCluster}#job_timeout" do
                Arachni::Options.browser_cluster.job_timeout = 5
                @worker = described_class.new
                @worker.job_timeout.should == 5
            end
        end

        describe :max_time_to_live do
            it 'sets how many jobs should be run before respawning' do
                @worker = described_class.new( max_time_to_live: 10 )
                @worker.max_time_to_live.should == 10
            end

            it "defaults to #{Arachni::OptionGroups::BrowserCluster}#worker_time_to_live" do
                Arachni::Options.browser_cluster.worker_time_to_live = 5
                @worker = described_class.new
                @worker.max_time_to_live.should == 5
            end
        end
    end

    describe '#run_job' do
        it 'processes jobs from #master' do
            subject.should receive(:run_job).with(custom_job)
            @cluster.queue( custom_job ){}
            @cluster.wait
        end

        it 'assigns #job to the running job' do
            job = nil
            @cluster.queue( custom_job ) do
                job = subject.job
            end
            @cluster.wait
            job.should == custom_job
        end

        context 'when the job finishes' do
            let(:page) { Arachni::Page.from_url(url)  }

            it 'clears the cached HTTP responses' do
                subject.preload page
                subject.preloads.should be_any
                subject.instance_variable_get(:@window_responses)

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.instance_variable_get(:@window_responses).should be_empty
            end

            it 'clears #preloads' do
                subject.preload page
                subject.preloads.should be_any

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.preloads.should be_empty
            end

            it 'clears #cache' do
                subject.cache page
                subject.cache.should be_any

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.cache.should be_empty
            end

            it 'clears #captured_pages' do
                subject.captured_pages << page

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.captured_pages.should be_empty
            end

            it 'clears #page_snapshots' do
                subject.page_snapshots << page

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.page_snapshots.should be_empty
            end

            it 'clears #page_snapshots_with_sinks' do
                subject.page_snapshots_with_sinks << page

                @cluster.queue( custom_job ) {}
                @cluster.wait

                subject.page_snapshots_with_sinks.should be_empty
            end

            it 'clears #on_new_page callbacks' do
                subject.on_new_page{}

                @cluster.queue( custom_job ) {}
                @cluster.wait

                (subject.on_new_page{}).size.should == 1
            end

            it 'clears #on_new_page_with_sink callbacks' do
                subject.on_new_page_with_sink{}

                @cluster.queue( custom_job ){}
                @cluster.wait

                (subject.on_new_page_with_sink{}).size.should == 1
            end

            it 'clears #on_response callbacks' do
                subject.on_response{}

                @cluster.queue( custom_job ){}
                @cluster.wait

                (subject.on_response{}).size.should == 1
            end

            it 'clears #on_fire_event callbacks' do
                subject.on_fire_event{}

                @cluster.queue( custom_job ){}
                @cluster.wait

                (subject.on_fire_event{}).size.should == 1
            end

            it 'removes #job' do
                @cluster.queue( custom_job ){}
                @cluster.wait
                subject.job.should be_nil
            end

            it 'decrements #time_to_live' do
                @cluster.queue( custom_job ) {}
                @cluster.wait
                subject.time_to_live.should == subject.max_time_to_live - 1
            end

            context 'when #time_to_live reaches 0' do
                it 'respawns the browser' do
                    @cluster.shutdown

                    Arachni::Options.browser_cluster.worker_time_to_live = 1
                    @cluster = Arachni::BrowserCluster.new( pool_size: 1 )

                    subject.max_time_to_live = 1

                    watir = subject.watir
                    browser_client = subject.watir.driver.instance_variable_get(:@bridge).
                        http.instance_variable_get(:@http)
                    browser_port = browser_client.port

                    @cluster.queue( custom_job ) {}
                    @cluster.wait

                    watir.should_not == subject.watir
                    browser_port.should_not == subject.watir.driver.
                        instance_variable_get(:@bridge).
                        http.instance_variable_get(:@http).port
                end
            end
        end

        context 'when the job takes more than #job_timeout' do
            it 'aborts it' do
                subject.job_timeout = 1
                @cluster.queue( sleep_job ) {}
                @cluster.wait
            end
        end
    end

end
