Vagrant.configure("2") do |config|
    if Vagrant.has_plugin?("vagrant-proxyconf")
      config.proxy.http     = "#{ENV['http_proxy']}"
      if ENV['https_proxy']
        config.proxy.https     = "#{ENV['https_proxy']}"
      else
        config.proxy.https     = "#{ENV['http_proxy']}"
      end
      config.proxy.no_proxy = "#{ENV['no_proxy']}"
    end
end