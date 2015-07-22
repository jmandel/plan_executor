require "selenium-webdriver"
require "headless"
require "securerandom"

module Crucible
  module Auth
    class CodeFlow
      def initialize(server, oauth, sign_in_strategy, approval_strategy)
        @client_id = oauth[:client_id]
        @client_secret = oauth[:client_secret]
        @redirect_uri = oauth[:redirect_uri]

        @sign_in_strategy = sign_in_strategy
        @approval_strategy = approval_strategy

        client = FHIR::Client.new(server)
        metadata = client.get_oauth2_metadata_from_conformance
        @authorize_url = "#{metadata[:site]}/#{metadata[:authorize_url]}"
        @token_url = "#{metadata[:site]}/#{metadata[:token_url]}"

        @headless = Headless.new
        @headless.start
        @driver = Selenium::WebDriver.for :firefox
      end

      def basic_auth(client_id, client_secret)
        'Basic ' + Base64.encode64(client_id + ':' + client_secret).gsub("\n", '')
      end

      def obtain_token(cfg)
        launch = cfg[:launch] # launch id
        client = OAuth2::Client.new(@client_id, @client_secret, :authorize_url => @authorize_url, :token_url => @token_url)

        authorize_url = client.auth_code.authorize_url(
          :redirect_uri => @redirect_uri, 
          :state => SecureRandom.hex,
          :scope => "patient/*.read launch:#{launch}")

        puts "authorze at #{authorize_url}"
        @driver.navigate.to authorize_url

        @sign_in_strategy.sign_in @driver
        approval_url = @driver.current_url

        @approval_strategy.approve @driver
        authz_response = Addressable::URI.parse(@driver.current_url).query_values

        @driver.quit
        @headless.destroy
        puts authz_response

        token_response = client.auth_code.get_token(
          authz_response["code"],
          :redirect_uri => @redirect_uri,
          :headers => {"Authorization" => basic_auth(@client_id, @client_secret)})

        puts token_response.params
        return token_response
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
        #puts driver.execute_script("return document.cookie")
        UsernamePasswordSignIn.fill(driver, @username_selector, @username)
        UsernamePasswordSignIn.fill(driver, @password_selector, @password)
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
      end

    end
  end
end
