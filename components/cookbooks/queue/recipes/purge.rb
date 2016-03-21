#check for amq

appresourcename = "#{node['queue']['destinationname']}"

env="localhost"

execute "purge ActiveMQ Queue" do
  cwd "#{node.workorder.payLoad[:activemq][0][:ciAttributes][:installpath]}/activemq"
  command "java -cp 'amq-messaging-resource.jar:*' io.strati.amq.MessagingResources -s '#{env}' -r purgequeue -dn #{appresourcename}"
  cmd = Mixlib::ShellOut.new(command).run_command
    if cmd.stdout.include? "failed"
       Chef::Log.error("Error occurred : #{cmd.stdout}")
      exit 1
    else
      Chef::Log.info("Execution completed: #{cmd.stdout}")
    end
  only_if { node.queue.resourcetype.strip.to_s == 'Q' }
end