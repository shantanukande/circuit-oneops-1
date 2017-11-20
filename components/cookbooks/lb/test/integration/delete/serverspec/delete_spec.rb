CIRCUIT_PATH="/opt/oneops/inductor/circuit-oneops-1"
COOKBOOKS_PATH="#{CIRCUIT_PATH}/components/cookbooks"
AZURE_TESTS_PATH="#{COOKBOOKS_PATH}/azure_lb/test/integration/delete/serverspec/tests"

require "#{CIRCUIT_PATH}/components/spec_helper.rb"
require "#{COOKBOOKS_PATH}/azure_base/test/integration/spec_utils"

provider = SpecUtils.new($node).get_provider
if provider =~ /azure/
  Dir.glob("#{AZURE_TESTS_PATH}/*.rb").each {|tst| require tst}
end
