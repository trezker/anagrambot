import std.stdio;
import std.socket;
import std.regex;
import std.algorithm;
import std.string;

void ParseIrcMessage(char[] rawmessage, out char[] nick, out char[] peer, out char[] command, out char[] message) {
	//:ragaman!~ragaman@h203n1-sde-a31.ias.bredband.telia.com JOIN ##anagram
	//PING :card.freenode.net
	nick = rawmessage[1 .. indexOf(rawmessage, "!")]; 
	peer = rawmessage[indexOf(rawmessage, "!") .. indexOf(rawmessage, " ")];
}

bool Send(Socket s, string msg) {
	auto result = s.send(msg);
	writeln("<", msg);
	return result != Socket.ERROR;
}

void main() {
	Socket s = new TcpSocket();
	s.connect(new InternetAddress("irc.freenode.net", 6667));

	if(!Send(s, "NICK ragaman\r\n")) {
		writeln("Failed send");
	}
	if(!Send(s, "USER ragaman 0 * :anagram bot\r\n")) {
		writeln("Failed send");
	}
	if(!Send(s, "JOIN ##anagram\r\n")) {
		writeln("Failed send");
	}

	while(true) {
		char[1024] buffer;
		auto received = s.receive(buffer);
		auto receivebuffer = buffer[0 .. received];
		//writeln("Received: ", received);
		writeln(">", receivebuffer);
		
		char[] nick;
		char[] peer;
		char[] command;
		char[] channel;
		char[] message;
		auto nickend = indexOf(receivebuffer, "!");
		if(nickend > -1 && startsWith(receivebuffer, ":")) {
			receivebuffer = stripRight(receivebuffer);
			writeln("parsing");
			nick = receivebuffer[1 .. nickend];
			peer = receivebuffer[nickend + 1 .. indexOf(receivebuffer, " ")];
			auto rbs = split(receivebuffer, ' ');
			command = rbs[1];
			channel = rbs[2];
			
			auto channelend = indexOf(receivebuffer, channel);
			if(channelend > -1 && channelend + channel.length + 2 < receivebuffer.length) {
				//writeln("Startpos: ", channelend + channel.length);
				//writeln(receivebuffer.length);
				message = receivebuffer[channelend + channel.length + 2 .. $];
			}
			
			//ParseIrcMessage(receivebuffer, nick, peer, command, message);
			writefln("Nick: '%s'", nick);
			writefln("Peer: '%s'", peer);
			writefln("Command: '%s'", command);
			writefln("Channel: '%s'", channel);
			writefln("Message: '%s'", message);

			if(command == "PRIVMSG") {
				if(nick == "Trezker") {
					if(message == "!quit")
						break;
				}
			}
		}
	}
	s.close();
}
