require 'rubygems'
require 'sinatra'

class Transaction
   attr_reader :clientRequest, :serverResponse, :clientRequestURI
   
   def initialize()
     @serverResponse = "";
     @clientRequest  = ""; 
   end
   
   def serverResponse=(response)
      @serverResponse = serverResponse
      @serverResponseStatus = getResponseStatus(serverResponse)
   end
   
   def clientRequest=(response)
      @clientRequest = clientRequest
      @clientRequestURI = getRequestURI(clientRequest)
   end

   private

   def getRequestURI(request)
      match = request.match(/\AGET ([^\n\r ]+) .+Host: ([^\n\r]+)/m)
      
      if !match.nil?
         match[2].concat(match[1])
      end
   end

   def getResponseStatus(response)
      match = request.match(/\AHTTP[^\r\n ] ([0-9]+ [^\r\n]+)/m)
      
      if !match.nil?
         match[1]
      end
   end
end

# This Middleware application serves up the requested captured HTTP response.
class MyMiddleware
   def initialize(app)
      @app = app
   end

   def call(env)
      if status == 999
         puts "crayzay"

         rack_input = Streams["3"].transactions[0].serverResponse
         env.update({"rack.input"=> rack_input})
      else
         puts "normal #{status}"
      end
      status, headers, body = @app.call(env)
      [status,headers,body]
   end
end

# Use wireshark to do initial parsing of the raw dump file. Our goal is to
# eventually mimic the "Follow Stream" behavior of the wireshark dialog box.
dumpFile = "testing/josiahland.wireshark.tcpdump"
parsedPackets = `tshark -r #{dumpFile} -R "tcp.stream && data" -T fields -e tcp.stream -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e data`
parsedPackets = parsedPackets.split("\n")

# We now have an array of individual packets. Let's separate these packets out
# into arrays of individual streams. The format of this array will be:
# "clientIP:port serverIP:port" => array of Transaction objects
Streams = Hash.new # The stream array
transactionMode = Hash.new # A temporary variable to keep track of the
# current stream directions

parsedPackets.each do |parsedPacket|
   parsedPacket = parsedPacket.split("\t")

   streamID = "#{parsedPacket[0]} #{parsedPacket[1]}:#{parsedPacket[2]} #{parsedPacket[3]}:#{parsedPacket[4]}"

   # Wireshark displays the packet payload as an ASCII hexadecimal digit. We're
   # going to change this back into a UTF-8 string
   packetBytes = Array.new
   packetData = parsedPacket[5].scan(/.{2}/)
   packetData.each do |chr|
      packetBytes.push(chr.hex)
   end
   packetData = packetBytes.pack("U*")

   # Switch stream directions on GET requests and HTTP responses
   if !packetData.match(/\AGET [^\r\n ]+/).nil?
      if transactionMode[streamID] == "clientRequest"
         abort("Got confused by two GET requests in a row.")
      end

      transactionMode[streamID] = "clientRequest"
      
      if !Streams.has_key?(streamID)
         Streams[streamID] = Array.new
      end
      Streams[streamID].push(Transaction.new)
   
   elsif transactionMode[streamID] == "clientRequest" && !packetData.match(/\AHTTP/).nil?
      trasactionMode[streamID] = "serverResponse"
      
   end # Switch stream directions

   if !Streams.has_key?(streamID)
      abort("Got confused by a stream with no GET request")
   end
   
   if trasactionMode[streamID] == "clientRequest"
      Streams[streamID].last.clientRequest += packetData
   else
      Streams[streamID].last.serverResponse += packetData
   end

end# Parse packets into Streams

# Start piping everything through the custom Middleware application we've built
# to serve up the captured HTTP responses
use MyMiddleware

get "/" do
# print Streams
   outputStr = String.new
   Streams.each_pair do |streamID, stream|
      outputStr << "<h1>#{streamID}</h1>\n"
      outputStr << "<ul>\n"

      stream.transactions.each do |transaction|
         outputStr << "<li><a href=\"#{transaction.clientRequestURI}\" title=\"#{transaction.clientRequest}\">#{transaction.clientRequestURI}</a></li>\n"
      end

      outputStr << "</ul>\n"
      outputStr << "\n\n"
   end# print Streams

   "<html><header><title>Hi</title></header><body>Hello World! You are a good world.\n<br />\n#{outputStr}</body></html>"
end

get %r{/bubba} do
   status 999
end
