require 'rubygems'
require 'sinatra'

class Stream
   attr_accessor :local, :remote, :packets, :responsePairs

   def initialize(local, remote, packets, responsePairs)
      @local = local
      @remote = remote
      @packets = packets
      @responsePairs = responsePairs
   end
end

class Packet
   attr_accessor :data, :direction

   def initialize(data, direction)
      @data = data
      @direction = direction
   end
end

class ResponsePair
   attr_accessor :request, :fullRequest, :response

   def initialize(request, fullRequest, response)
      @request = request
      @fullRequest = fullRequest
      @response = response
   end
end

class MyMiddleware
   def initialize(app)
      @app = app
   end

   def call(env)
      status, headers, body = @app.call(env)

      if status == 999
         puts "crayzay"
         response = Rack::Response.new
         response.write Streams["3"].responsePairs[0].response
         response.finish
      else
         [status,headers,body]
      end
   end
end

dumpFile = "testing/josiahland.wireshark.tcpdump"
parsedPackets = `tshark -r #{dumpFile} -R "tcp.stream && data" -T fields -e tcp.stream -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e data`
parsedPackets = parsedPackets.split("\n")
Streams = Hash.new

# parse packets into Streams
parsedPackets.each do |parsedPacket|
   parsedPacket = parsedPacket.split("\t")

   streamID = parsedPacket[0]
   source = "#{parsedPacket[1]}:#{parsedPacket[2]}"
   dest   = "#{parsedPacket[3]}:#{parsedPacket[4]}"


   packetBytes = Array.new
   packetData = parsedPacket[5].scan(/.{2}/)
   packetData.each do |chr|
      packetBytes.push(chr.hex)
   end
   packetData = packetBytes.pack("U*")

   if !packetData.match(/\AGET [^\n]+ HTTP/).nil?
      if !Streams.has_key?(streamID)
         Streams[streamID] = Stream.new(source, dest, Array.new, Array.new)
      end
   end

   if Streams.has_key?(streamID)
      direction = ">"
      if source == Streams[streamID].remote
         direction = "<"
      end

      if Streams[streamID].packets.size == 0 || (direction == ">" && Streams[streamID].packets.last.direction == "<")
         match = packetData.match(/\AGET ([^\r\n]+) HTTP.+\r?\nHost: ([^\r\n]+)/m)
         Streams[streamID].responsePairs.push(ResponsePair.new(match[2].concat(match[1]),"",""))
      end

      if direction == ">"
         Streams[streamID].responsePairs.last.fullRequest.concat(packetData)
      else
         Streams[streamID].responsePairs.last.response.concat(packetData)
      end

      Streams[streamID].packets.push(Packet.new(packetData, direction))
   end # if

end # parse packets into Streams


# parse Streams into response pairs
responses = Array.new
Streams.each_value do |stream|
   
end # parse Streams into response pairs

use MyMiddleware

get "/" do
   # print Streams
   outputStr = String.new
   Streams.each_pair do |streamID, stream|      
      outputStr << "############ (#{streamID}) #{stream.local} -> #{stream.remote} #############\n(#{stream.packets.size} packets, #{stream.responsePairs.size} response pairs)\n"
      outputStr << "<ul>\n"
      counter = 0
      stream.responsePairs.each do |responsePair|
         #outputStr << "Pair %d:\n   REQUEST{\n%s\n   }REQUEST\n   RESPONSE{\n%s\n   }RESPONSE\n" % [counter, responsePair.request, responsePair.response]
         outputStr << "<li><a href=\"#{responsePair.request}\" title=\"#{responsePair.fullRequest}\">#{responsePair.request}</a></li>\n"
         counter += 1
      end
      outputStr << "</ul>\n"

      outputStr << "\n\n"
   end # print Streams


   "<html><header><title>Hi</title></header><body>Hello World! You are a good world.\n\n#{outputStr}</body></html>"
end

get %r{/(.+)} do
   status 999
end
