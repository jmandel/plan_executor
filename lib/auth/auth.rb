require "selenium-webdriver"

module Crucible
  module Auth
    class CodeFlow
      def initialize(server, oauth, sign_in_strategy, approval_strategy)
        @client_id = oauth[:client_id]
        @client_secret = oauth[:client_secret]

        client = FHIR::Client.new(server)
        options = client.get_oauth2_metadata_from_conformance
        @authorize_url = "#{options[:site]}/#{options[:authorize_url]}"
        @token_url = "#{options[:site]}/#{options[:token_url]}"

        puts "Got oauth options #{options}"
        @sign_in_strategy = sign_in_strategy
        @approval_strategy = approval_strategy
      end
    
      def obtain_token(cfg)
        launch = cfg[:launch] # launch id
        driver = Selenium::WebDriver.for :phantomjs
        url = "#{@authorize_url}?client_id=#{@client_id}&response_type=code&state=abc&scope=launch:#{launch} patient/*.read"
        puts "nav to #{url}"
        driver.navigate.to url
        @sign_in_strategy.sign_in driver

        url = driver.current_url
        puts "on url #{url}"
        @approval_strategy.approve driver

        puts "Title #{driver.title}"
        puts driver.current_url
        puts "sleeping"
        sleep 2.0
        #wait = Selenium::WebDriver::Wait.new(:timeout => 3) # seconds
        #wait.until { driver.current_url != url }
        puts "Title #{driver.title}"
        puts driver.current_url
        puts driver.execute_script("return document.getElementsByTagName('html')[0].innerHTML")
        puts driver.execute_script("return document.cookie")

        return driver.current_url
      end

    end
  end
end

module Crucible
  module Auth
    class UsernamePasswordSignIn
      def initialize(cfg)
        @username = cfg[:username]
        @password = cfg[:password]
        @username_selector = cfg[:username_selector]
        @password_selector = cfg[:password_selector]
        @submit_selector = cfg[:submit_selector]
      end

      def sign_in(driver)
        puts driver.execute_script("return document.cookie")
        UsernamePasswordSignIn.fill(driver, @username_selector, @username)
        UsernamePasswordSignIn.fill(driver, @password_selector, @password)
        puts driver.title
        driver.find_element(:css, @submit_selector).click
      end

      def self.fill(driver, selector, value)
        elt = driver.find_element(:css, selector)
        elt.send_keys value
      end

    end
  end
end

module Crucible
  module Auth
    class ClickToApprove
      def initialize(cfg)
        @click_selectors = cfg[:click_selectors]
      end

      def approve(driver)
        @click_selectors.each do |selector|
          puts "clicking #{selector}"
          driver.find_element(:css, selector).click
        end
        puts driver.execute_script("$('#user_oauth_approval').attr('value',true)")
        puts "Set true"
        puts driver.execute_script("return $('#user_oauth_approval').attr('value')")
        puts driver.execute_script("return document.cookie")
        driver.execute_script("document.querySelector('form').submit()")
      end

    end
  end
end
