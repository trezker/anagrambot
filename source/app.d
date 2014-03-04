import std.stdio;
import std.socket;
import std.regex;
import std.algorithm;
import std.string;
import std.random;
import std.conv;

// /usr/share/dict/words

dstring[] Load_dictionary() {
	writeln("Loading dictionary from '/usr/share/dict/words'");
	auto f = File("/usr/share/dict/words");
	scope(exit) f.close();
	dstring[] lines;

	foreach (str; f.byLine) {
		lines ~= to!dstring(str.idup);
	}

	return lines;
}

bool Privmsg(Socket s, string channel, string msg) {
	return Send(s, ("PRIVMSG " ~ channel ~ " :" ~ msg).idup);
}

bool Send(Socket s, string msg) {
	auto result = s.send((msg ~ "\r\n").idup);
	writeln("<", msg);
	return result != Socket.ERROR;
}

void main() {
	dstring[] dict = Load_dictionary();
	dchar[] currentword;
	dchar[] shuffledword;
	
	Socket s = new TcpSocket();
	s.connect(new InternetAddress("irc.freenode.net", 6667));

	if(!Send(s, "NICK ragaman")) {
		writeln("Failed send");
	}
	if(!Send(s, "USER ragaman 0 * :anagram bot")) {
		writeln("Failed send");
	}
	if(!Send(s, "JOIN ##anagram")) {
		writeln("Failed send");
	}

	while(true) {
		char[1024] buffer;
		auto received = s.receive(buffer);
		auto receivebuffer = buffer[0 .. received];
		//writeln("Received: ", received);
		writeln(">", receivebuffer);
		
		if(startsWith(receivebuffer, "PING")) {
			receivebuffer[1] = 'O';
			Send(s, receivebuffer.dup);
		}
		
		auto nickend = indexOf(receivebuffer, "!");
		if(nickend > -1 && startsWith(receivebuffer, ":")) {
			char[] nick;
			char[] peer;
			char[] command;
			char[] channel;
			char[] message;
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
					if(message == "!quit") {
						Privmsg(s, channel.idup, "Shutting down");
						break;
					}
				}
				if(message == "!start") {
					ulong number = uniform(0, dict.length);
					currentword = dict[number].dup;
					shuffledword = dict[number].dup;
					randomShuffle(shuffledword);
					Privmsg(s, channel.idup, ("Number: " ~ to!string(number)).idup);
					Privmsg(s, channel.idup, ("Word: " ~ to!string(currentword)));
					Privmsg(s, channel.idup, ("Word: " ~ to!string(shuffledword)));
				}
			}
		}
	}
	s.close();
}
