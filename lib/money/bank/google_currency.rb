require 'money'
require 'money/rates_store/rate_removal_support'
require 'open-uri'

class Money
  module Bank
    # Raised when there is an unexpected error in extracting exchange rates
    # from Google Finance Calculator
    class GoogleCurrencyFetchError < Error
    end
    # Raised when there is a captcha form request in extracting exchange rates
    # from Google Finance Calculator
    class GoogleCurrencyCaptchaError < Error
    end

    class GoogleCurrency < Money::Bank::VariableExchange

      SERVICE_HOST = "free.currencyconverterapi.com"
      SERVICE_PATH = "/api/v5/convert"


      # @return [Hash] Stores the currently known rates.
      attr_reader :rates


      class << self
        # @return [Integer] Returns the Time To Live (TTL) in seconds.
        attr_reader :ttl_in_seconds

        # @return [Time] Returns the time when the rates expire.
        attr_reader :rates_expiration

        ##
        # Set the Time To Live (TTL) in seconds.
        #
        # @param [Integer] the seconds between an expiration and another.
        def ttl_in_seconds=(value)
          @ttl_in_seconds = value
          refresh_rates_expiration! if ttl_in_seconds
        end

        ##
        # Set the rates expiration TTL seconds from the current time.
        #
        # @return [Time] The next expiration.
        def refresh_rates_expiration!
          @rates_expiration = Time.now + ttl_in_seconds
        end
      end

      def initialize(*)
        super
        @store.extend Money::RatesStore::RateRemovalSupport
      end

      ##
      # Clears all rates stored in @rates
      #
      # @return [Hash] The empty @rates Hash.
      #
      # @example
      #   @bank = GoogleCurrency.new  #=> <Money::Bank::GoogleCurrency...>
      #   @bank.get_rate(:USD, :EUR)  #=> 0.776337241
      #   @bank.flush_rates           #=> {}
      def flush_rates
        store.clear_rates
      end

      ##
      # Clears the specified rate stored in @rates.
      #
      # @param [String, Symbol, Currency] from Currency to convert from (used
      #   for key into @rates).
      # @param [String, Symbol, Currency] to Currency to convert to (used for
      #   key into @rates).
      #
      # @return [Float] The flushed rate.
      #
      # @example
      #   @bank = GoogleCurrency.new    #=> <Money::Bank::GoogleCurrency...>
      #   @bank.get_rate(:USD, :EUR)    #=> 0.776337241
      #   @bank.flush_rate(:USD, :EUR)  #=> 0.776337241
      def flush_rate(from, to)
        store.remove_rate(from, to)
      end

      ##
      # Returns the requested rate.
      #
      # It also flushes all the rates when and if they are expired.
      #
      # @param [String, Symbol, Currency] from Currency to convert from
      # @param [String, Symbol, Currency] to Currency to convert to
      #
      # @return [Float] The requested rate.
      #
      # @example
      #   @bank = GoogleCurrency.new  #=> <Money::Bank::GoogleCurrency...>
      #   @bank.get_rate(:USD, :EUR)  #=> 0.776337241
      def get_rate(from, to)
        expire_rates
        store.get_rate(from, to) || store.add_rate(from, to, fetch_rate(from, to))
      end

      ##
      # Flushes all the rates if they are expired.
      #
      # @return [Boolean]
      def expire_rates
        if self.class.ttl_in_seconds && self.class.rates_expiration <= Time.now
          flush_rates
          self.class.refresh_rates_expiration!
          true
        else
          false
        end
      end

      private

      ##
      # Queries for the requested rate and returns it.
      #
      # @param [String, Symbol, Currency] from Currency to convert from
      # @param [String, Symbol, Currency] to Currency to convert to
      #
      # @return [BigDecimal] The requested rate.
      def fetch_rate(from, to)
        from, to = Currency.wrap(from), Currency.wrap(to)
        data = JSON.parse(build_uri(from, to).read)
        #Petición antigua para solicitar un contenido HTML y scrapear
        #data = build_uri(from, to).read
        rate = extract_rate(data);

        if (rate < 0.1)
          rate = 1/extract_rate(build_uri(to, from).read)
        end

        rate
      end

      ##
      # Build a URI for the given arguments.
      #
      # @param [Currency] from The currency to convert from.
      # @param [Currency] to The currency to convert to.
      #
      # @return [URI::HTTP]
      def build_uri(from, to)
        uri = URI::HTTP.build(
          :host  => SERVICE_HOST,
          :path  => SERVICE_PATH,
          :query => "q=#{from}_#{to}&compact=y"
          #Query antigua de xe conversor
          #:query => "Amount=1&From=#{from.iso_code}&To=#{to.iso_code}"
        )
      end

      ##
      # Takes the response from Google and extract the rate.
      #
      # @param [String] data The google rate string to decode.
      #
      # @return [BigDecimal]
      def extract_rate(data)
        value = data.values.first["val"]
        if value.present?
          return value
        else
          raise GoogleCurrencyFetchError
        end

#El primer bloque comentado corresponde al scraping sobre la URL de xe conversor y estuvo funcionando hasta que cargaron por react el factor de conversión
#El segundo bloque corresponde a la forma primitiva de la gema de extraer de google finance la conversión adaptada a xe conversor
=begin        
        value = data.scan(/<span class='uccResultAmount'.+?span>/)
        if value.present?
          BigDecimal value.first.scan(/\d+\.?\d*/).last
        else
          raise GoogleCurrencyFetchError
        end
=end
=begin
        case data
        when /<span class=uccResultAmount>(\d+\.?\d*)<\/span>/
          BigDecimal($1)
        when /Could not convert\./
          raise UnknownRate
        when /captcha-form/
          raise GoogleCurrencyCaptchaError
        else
          raise GoogleCurrencyFetchError
        end
=end
      end
    end
  end
end

