require 'rubygems'
require 'sinatra'
require 'thin'

class Transaction
   attr_accessor :request, :response
end

class Response
   attr_reader :status
   attr_accessor :headers, :body
   
   def initialize(status)
      @status = status
   end
end

class Request
   attr_reader :path
   attr_accessor :headers, :body
   
   def initialize(path)
      @path = path
   end
end

# Use wireshark to do initial parsing of the raw dump file. Our goal is to
# eventually mimic the "Follow Stream" behavior of the wireshark dialog box.
dumpFile = "testing/josiahland.wireshark.tcpdump"
parsedPackets = `tshark -r #{dumpFile} -R "tcp.stream && data" -T fields -e tcp.stream -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e data`
parsedPackets = parsedPackets.split("\n")

# We now have an array of individual packets. Let's separate these packets out
# into arrays of individual streams. The stream arrays will contain elements
# which alternate in direction.
streamData = Hash.new
streamDirs = Hash.new

parsedPackets.each do |parsedPacket|
   parsedPacket = parsedPacket.split("\t")

   streamID = parsedPacket[0]
   fromAddr = "#{parsedPacket[1]}:#{parsedPacket[2]}"
   toAddr = "#{parsedPacket[3]}:#{parsedPacket[4]}"
   
   if !streamData.has_key?(streamID)
      streamData[streamID] = [parsedPacket[5]]
      streamDirs[streamID] = [fromAddr,toAddr] 
   
   # Direction switches, so make a new element
   elsif streamDirs[streamID][0] != fromAddr
      streamData[streamID].push(parsedPacket[5])
      streamDirs[streamID] = [fromAddr,toAddr]
      
   # Direction remains the same, so append to the previous element
   else
      streamData[streamID].last += parsedPacket[5]
   end
end# Parse packets into streams

streams = Hash.new
streamData.each_pair do |streamID, stream|
   
   # Wireshark displays the packet payload as an ASCII hexadecimal digit. We need
   # to parse the header to determine who is the client and who is the server
   counter = 0
   stream.each do |data|
      
      # Mode is as follows: 0 = first line
      #                     1 = header
      #                     2 = body
      mode = 1
      bodyBytes = Array.new
      lineBytes = Array.new
      bytesStr = data.scan(/.{2}/)
      
      bytesStr.each do |byteStr|
         byte = byteStr.hex
         
         if mode < 2
            lineBytes.push(byte)
            
            # CR+LF
            if lineBytes.size >= 2 && lineBytes[lineBytes.size - 2] == 0x0D && lineBytes[lineBytes.size - 1] == 0x0A
               currentLine = lineBytes.pack("C*")
               
               # If we are looking for the first line
               if mode == 0
                  matches = currentLine.match(/^GET ([^\n\r ]+)/)
                  
                  # Is the first line a request?
                  if !matches.nil?
                     path = matches[1]
                     
                     # Determine which is the server and which is the client based on our current position in the array and the size of the array
                     # This can be done because the to and from positions switch with each element of the array
                     fromAddr = streamDirs[streamID][(stream.size - count) % 2]
                     toAddr = streamDirs[streamID][~((stream.size - count) % 2) & 0x1]
                     streamDirs[streamID] = [toAddr, fromAddr]
                     
                     if !streams.has_key?(streamID)
                        streams[streamID] = Array.new
                     end
                     
                     streams[streamID].push(Transaction.new)
                     streams[streamID].last.request = Request.new(path)
                     
                  # Is the first line a response to a previous request?
                  elsif streams.has_key?(streamID)
                     matches = currentLine.match(/^HTTP ([^\n\r ]+)/)
                     
                     if !matches.nil?
                     status = matches[1]
                     streams[streamID].last.response = Response.new(status)
                     
                     # Ignore responses for which we have no corresponding request.
                     else
                        puts "Ignoring packet from #{streamDirs[streamID]} because first line is [#{currentLine.chomp}]"
                        break
                     end
                     
                  end
                  
                  # We have found the first line. Time to move on to the header
                  mode = 1
               
               # If we are looking for the headers (mode == 1)
               else
                  # If we encounter a blank line, we have finished with the headers. Time to move on to the body
                  if lineBytes.size == 2
                     mode = 2
                  else
                     matches = currentLine.match(/^([^: ]): ([^\r\n]+)/)
                     
                     # Differentiate between requests and responses
                     if !streams[streamID].last.response.nil?
                        streams[streamID].last.response.headers[matches[1]] = matches[2]
                     else
                        streams[streamID].last.request.headers[matches[1]] = matches[2]
                     end
                  end
               end
               
               lineBytes = Array.new
            end
         
         # (mode == 2)
         else
            # Differentiate between requests and responses
            if !streams.last.response.nil?
               streams.last.response.bodyBytes.push(byte)
            else
               streams.last.request.bodyBytes.push(byte)
            end
         end
      end
      
      counter += 1
   end
   
end

# This Middleware application serves up the requested captured HTTP response.
class MyMiddleware
   def initialize(app)
      @app = app
   end

   def call(env)
      rack_input = String.new
      
      if env["QUERY_STRING"] == "bubba"
         puts "crayzay web response "
         #[status, headers, body]
      else
         puts "normal web response"
      end
      
      @app.call(env)
   end
end

# Start piping everything through the custom Middleware application we've built
# to serve up the captured HTTP responses
use MyMiddleware

get "/" do
# print $streams
   outputStr = String.new
   $streamInfo.each do |sinfo|
      outputStr << "<h1>#{sinfo["client"]} <-- #{sinfo["server"]} (#{sinfo["streamID"]})</h1>\n"
      outputStr << "<ul>\n"

      $streams[sinfo["streamID"]].each do |transaction|
         outputStr << "<li><a href=\"#{transaction.clientRequestURI}\" title=\"#{transaction.clientRequest}\">#{transaction.clientRequestURI}</a></li>\n"
      end

      outputStr << "</ul>\n"
      outputStr << "\n\n"
   end# print $streams

   "<html><header><title>Hi</title></header><body>Hello World! You are a good world.\n<br />\n#{outputStr}</body></html>"
end
