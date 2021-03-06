
require 'base64'
require 'uri'
require 'riak/client'
require 'riak/util/headers'

module Riak
  class Client
    class HTTPBackend
      # Methods related to performing HTTP requests in a consistent
      # fashion across multiple client libraries. HTTP/1.1 verbs are
      # presented as methods.
      module TransportMethods
        # Performs a HEAD request to the specified resource on the Riak server.
        # @param [Fixnum, Array] expect the expected HTTP response code(s) from Riak
        # @param [String, Array<String,Hash>] resource a relative path or array of path segments and optional query params Hash that will be joined to the root URI
        # @overload head(expect, *resource)
        # @overload head(expect, *resource, headers)
        #   Send the request with custom headers
        #   @param [Hash] headers custom headers to send with the request
        # @return [Hash] response data, containing only the :headers and :code keys
        # @raise [FailedRequest] if the response code doesn't match the expected response
        def head(expect, *resource)
          headers = default_headers.merge(resource.extract_options!)
          verify_path!(resource)
          perform(:head, path(*resource), headers, expect)
        end

        # Performs a GET request to the specified resource on the Riak server.
        # @param [Fixnum, Array] expect the expected HTTP response code(s) from Riak
        # @param [String, Array<String,Hash>] resource a relative path or array of path segments and optional query params Hash that will be joined to the root URI
        # @overload get(expect, *resource)
        # @overload get(expect, *resource, headers)
        #   Send the request with custom headers
        #   @param [Hash] headers custom headers to send with the request
        # @overload get(expect, *resource, headers={})
        #   Stream the response body through the supplied block
        #   @param [Hash] headers custom headers to send with the request
        #   @yield [chunk] yields successive chunks of the response body as strings
        #   @return [Hash] response data, containing only the :headers and :code keys
        # @return [Hash] response data, containing :headers, :body, and :code keys
        # @raise [FailedRequest] if the response code doesn't match the expected response
        def get(expect, *resource, &block)
          headers = default_headers.merge(resource.extract_options!)
          verify_path!(resource)
          perform(:get, path(*resource), headers, expect, &block)
        end

        # Performs a PUT request to the specified resource on the Riak server.
        # @param [Fixnum, Array] expect the expected HTTP response code(s) from Riak
        # @param [String, Array<String,Hash>] resource a relative path or array of path segments and optional query params Hash that will be joined to the root URI
        # @param [String] body the request body to send to the server
        # @overload put(expect, *resource, body)
        # @overload put(expect, *resource, body, headers)
        #   Send the request with custom headers
        #   @param [Hash] headers custom headers to send with the request
        # @overload put(expect, *resource, body, headers={})
        #   Stream the response body through the supplied block
        #   @param [Hash] headers custom headers to send with the request
        #   @yield [chunk] yields successive chunks of the response body as strings
        #   @return [Hash] response data, containing only the :headers and :code keys
        # @return [Hash] response data, containing :headers, :code, and :body keys
        # @raise [FailedRequest] if the response code doesn't match the expected response
        def put(expect, *resource, &block)
          headers = default_headers.merge(resource.extract_options!)
          uri, data = verify_path_and_body!(resource)
          perform(:put, path(*uri), headers, expect, data, &block)
        end

        # Performs a POST request to the specified resource on the Riak server.
        # @param [Fixnum, Array] expect the expected HTTP response code(s) from Riak
        # @param [String, Array<String>] resource a relative path or array of path segments that will be joined to the root URI
        # @param [String] body the request body to send to the server
        # @overload post(expect, *resource, body)
        # @overload post(expect, *resource, body, headers)
        #   Send the request with custom headers
        #   @param [Hash] headers custom headers to send with the request
        # @overload post(expect, *resource, body, headers={})
        #   Stream the response body through the supplied block
        #   @param [Hash] headers custom headers to send with the request
        #   @yield [chunk] yields successive chunks of the response body as strings
        #   @return [Hash] response data, containing only the :headers and :code keys
        # @return [Hash] response data, containing :headers, :code and :body keys
        # @raise [FailedRequest] if the response code doesn't match the expected response
        def post(expect, *resource, &block)
          headers = default_headers.merge(resource.extract_options!)
          uri, data = verify_path_and_body!(resource)
          perform(:post, path(*uri), headers, expect, data, &block)
        end

        # Performs a DELETE request to the specified resource on the Riak server.
        # @param [Fixnum, Array] expect the expected HTTP response code(s) from Riak
        # @param [String, Array<String,Hash>] resource a relative path or array of path segments and optional query params Hash that will be joined to the root URI
        # @overload delete(expect, *resource)
        # @overload delete(expect, *resource, headers)
        #   Send the request with custom headers
        #   @param [Hash] headers custom headers to send with the request
        # @overload delete(expect, *resource, headers={})
        #   Stream the response body through the supplied block
        #   @param [Hash] headers custom headers to send with the request
        #   @yield [chunk] yields successive chunks of the response body as strings
        #   @return [Hash] response data, containing only the :headers and :code keys
        # @return [Hash] response data, containing :headers, :code and :body keys
        # @raise [FailedRequest] if the response code doesn't match the expected response
        def delete(expect, *resource, &block)
          headers = default_headers.merge(resource.extract_options!)
          verify_path!(resource)
          perform(:delete, path(*resource), headers, expect, &block)
        end

        # Executes requests according to the underlying HTTP client library semantics.
        # @abstract Subclasses must implement this internal method to perform HTTP requests
        #           according to the API of their HTTP libraries.
        # @param [Symbol] method one of :head, :get, :post, :put, :delete
        # @param [URI] uri the HTTP URI to request
        # @param [Hash] headers headers to send along with the request
        # @param [Fixnum, Array] expect the expected response code(s)
        # @param [String, #read] body the PUT or POST request body
        # @return [Hash] response data, containing :headers, :code and :body keys. Only :headers and :code should be present when the body is streamed or the method is :head.
        # @yield [chunk] if the method is not :head, successive chunks of the response body will be yielded as strings
        # @raise [NotImplementedError] if a subclass does not implement this method
        def perform(method, uri, headers, expect, body=nil)
          raise NotImplementedError
        end

        # Default header hash sent with every request, based on settings in the client
        # @return [Hash] headers that will be merged with user-specified headers on every request
        def default_headers
          {
            "Accept" => "multipart/mixed, application/json;q=0.7, */*;q=0.5",
            "X-Riak-ClientId" => client_id
          }.merge(basic_auth_header)
        end

        def client_id
          value = @client.client_id
          case value
          when Integer
            b64encode(value)
          when String
            value
          end
        end

        def basic_auth_header
          @client.basic_auth ? {"Authorization" => "Basic #{Base64::encode64(@client.basic_auth)}"} : {}
        end

        # @return [URI] The calculated root URI for the Riak HTTP endpoint
        def root_uri
          protocol = client.ssl_enabled? ? "https" : "http"
          URI.parse("#{protocol}://#{client.host}:#{client.http_port}")
        end

        # Calculates an absolute URI from a relative path specification
        # @param [Array<String,Hash>] segments a relative path or sequence of path segments and optional query params Hash that will be joined to the root URI
        # @return [URI] an absolute URI for the resource
        def path(*segments)
          query = segments.extract_options!.to_param
          root_uri.merge(segments.join("/").gsub(/\/+/, "/").sub(/^\//, '')).tap do |uri|
            uri.query = query if query.present?
          end
        end

        # Verifies that both a resource path and body are present in the arguments
        # @param [Array] args the arguments to verify
        # @raise [ArgumentError] if the body or resource is missing, or if the body is not a String
        def verify_path_and_body!(args)
          body = args.pop
          begin
            verify_path!(args)
          rescue ArgumentError
            raise ArgumentError, t("path_and_body_required")
          end

          raise ArgumentError, t("request_body_type") unless String === body || body.respond_to?(:read)
          [args, body]
        end

        # Verifies that the specified resource is valid
        # @param [String, Array] resource the resource specification
        # @raise [ArgumentError] if the resource path is too short
        def verify_path!(resource)
          resource = Array(resource).flatten
          raise ArgumentError, t("resource_path_short") unless resource.length > 1 || resource.include?(@client.mapred)
        end

        # Checks the expected response codes against the actual response code. Use internally when
        # implementing {#perform}.
        # @param [String, Fixnum, Array<String,Fixnum>] expected the expected response code(s)
        # @param [String, Fixnum] actual the received response code
        # @return [Boolean] whether the actual response code is acceptable given the expectations
        def valid_response?(expected, actual)
          Array(expected).map(&:to_i).include?(actual.to_i)
        end

        # Checks whether a combination of the HTTP method, response code, and block should
        # result in returning the :body in the response hash. Use internally when implementing {#perform}.
        # @param [Symbol] method the HTTP method
        # @param [String, Fixnum] code the received response code
        # @param [Boolean] has_block whether a streaming block was passed to {#perform}. Pass block_given? to this parameter.
        # @return [Boolean] whether to return the body in the response hash
        def return_body?(method, code, has_block)
          method != :head && !valid_response?([204,205,304], code) && !has_block
        end

        private
        def response_headers
          Thread.current[:response_headers] ||= Riak::Util::Headers.new
        end

        def b64encode(n)
          Base64.encode64([n].pack("N")).chomp
        end
      end
    end
  end
end
