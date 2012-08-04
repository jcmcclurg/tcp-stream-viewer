require 'rubygems'
require 'sinatra'

class Stream
   attr_accessor :client, :server, :packets, :transactions

   def initialize(client, server, transactions)
      @client = client
      @server = server
      @transactions = transactions
   end
end

class Packet
   attr_accessor :data, :direction

   def initialize(data, direction)
      @data = data
      @direction = direction
   end
end

class Transaction
   attr_accessor :clientRequest, :serverResponse

   def initialize(clientRequest, serverResponse)
      @clientRequest = clientRequest
      @serverResponse = serverResponse
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
         
         serverResponse = Rack::serverResponse.new
         serverResponse.body = Streams["3"].transactions[0].serverResponse
         serverResponse.finish
      else
         puts "normal #{status}"
         
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
      if source == Streams[streamID].server
         direction = "<"
      end

      if Streams[streamID].packets.size == 0 || (direction == ">" && Streams[streamID].packets.last.direction == "<")
         match = packetData.match(/\AGET ([^\r\n]+) HTTP.+\r?\nHost: ([^\r\n]+)/m)
         Streams[streamID].transactions.push(transaction.new(match[2].concat(match[1]),"",""))
      end

      if direction == ">"
         Streams[streamID].transactions.last.fullclientRequest.concat(packetData)
      else
         Streams[streamID].transactions.last.serverResponse.concat(packetData)
      end

      Streams[streamID].packets.push(Packet.new(packetData, direction))
   end # if

end # parse packets into Streams


# parse Streams into serverResponse pairs
serverResponses = Array.new
Streams.each_value do |stream|
   
end # parse Streams into serverResponse pairs

use MyMiddleware

get "/" do
   # print Streams
   outputStr = String.new
   Streams.each_pair do |streamID, stream|      
      outputStr << "############ (#{streamID}) #{stream.client} -> #{stream.server} #############\n(#{stream.packets.size} packets, #{stream.transactions.size} serverResponse pairs)\n"
      outputStr << "<ul>\n"
      counter = 0
      stream.packets.each do |packet|
        outputStr << "<li><code>#{packet.data.encode({:xml => :text})}</code></li>"
        counter += 1
      end
=begin
      stream.transactions.each do |transaction|
         outputStr << "<li><a href=\"#{transaction.clientRequest}\" title=\"#{transaction.fullclientRequest}\">#{transaction.clientRequest}</a></li>\n"
         counter += 1
      end
=end
      outputStr << "</ul>\n"
      outputStr << "\n\n"
   end # print Streams


   "<html><header><title>Hi</title></header><body>Hello World! You are a good world.\n\n#{outputStr}</body></html>"
end

get %r{/bubba} do
   status 999
end
