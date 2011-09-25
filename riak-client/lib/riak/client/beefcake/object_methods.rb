require 'riak/robject'
require 'riak/link'
require 'riak/client/beefcake/messages'

module Riak
  class Client
    class BeefcakeProtobuffsBackend
      module ObjectMethods
        ENCODING = "Riak".respond_to?(:encoding)

        # Returns RpbPutReq
        def dump_object(robject)
          pbuf = RpbPutReq.new(:bucket => maybe_encode(robject.bucket.name))
          pbuf.key = maybe_encode(robject.key ||= generate_key)
          pbuf.vclock = maybe_encode Base64.decode64(robject.vclock) if robject.vclock
          pbuf.content = RpbContent.new(:value => maybe_encode(robject.raw_data),
                                        :content_type => maybe_encode(robject.content_type),
                                        :links => robject.links.map {|l| encode_link(l) }.compact)

          pbuf.content.usermeta = robject.meta.map {|k,v| encode_pair(k,v)} if robject.meta.any?
          pbuf.content.indexes = robject.index.map {|k,v| encode_pair(k,v)} if robject.index.any?
          pbuf.content.vtag = maybe_encode(robject.etag) if robject.etag.present?
          if ENCODING # 1.9 support
            pbuf.content.charset = maybe_encode(robject.raw_data.encoding.name)
          end
          pbuf
        end

        # Returns RObject
        def load_object(pbuf, robject)
          robject.vclock = Base64.encode64(pbuf.vclock).chomp if pbuf.vclock
          if pbuf.content.size > 1
            robject.conflict = true
            robject.siblings = pbuf.content.map do |c|
              sibling = RObject.new(robject.bucket, robject.key)
              sibling.vclock = robject.vclock
              load_content(c, sibling)
            end

            return robject.attempt_conflict_resolution
          else
            load_content(pbuf.content.first, robject)
          end
          robject
        end

        private
        def load_content(pbuf, robject)
          if ENCODING && pbuf.charset.present?
            pbuf.value.force_encoding(pbuf.charset) if Encoding.find(pbuf.charset)
          end
          robject.raw_data = pbuf.value
          robject.etag = pbuf.vtag if pbuf.vtag.present?
          robject.content_type = pbuf.content_type if pbuf.content_type.present?
          robject.links = pbuf.links.map(&method(:decode_link)) if pbuf.links.present?
          pbuf.usermeta.each {|pair| decode_pair(pair, robject.meta) } if pbuf.usermeta.present?
          pbuf.indexes.each {|pair| decode_pair(pair, robject.index) } if pbuf.indexes.present?
          if pbuf.last_mod.present?
            robject.last_modified = Time.at(pbuf.last_mod)
            robject.last_modified += pbuf.last_mod_usecs / 1000000 if pbuf.last_mod_usecs.present?
          end
          robject
        end

        def decode_link(pbuf)
          Riak::Link.new(pbuf.bucket, pbuf.key, pbuf.tag)
        end

        def encode_link(link)
          return nil unless link.key.present?
          RpbLink.new(:bucket => maybe_encode(link.bucket.to_s),
                      :key => maybe_encode(link.key.to_s),
                      :tag => maybe_encode(link.tag.to_s))
        end

        def decode_pair(pbuf, hash)
          hash[pbuf.key] = pbuf.value
        end

        def encode_pair(key,value)
          return nil unless value.present?
          RpbPair.new(:key => maybe_encode(key.to_s),
                      :value => maybe_encode(value.to_s))
        end

        def maybe_encode(string)
          ENCODING ? string.encode('BINARY') : string
        end
      end

      include ObjectMethods
    end
  end
end
