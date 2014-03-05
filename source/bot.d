import std.socket;
import std.stdio;
import std.datetime;
import std.conv;
import std.random;
import std.string;

class Bot {
private:
	Socket socket;
	bool connected = false;
	string channel;
	dstring[] dictionary;
	StopWatch inactivitysw;
	StopWatch sw;
	dchar[] currentword;
	dchar[] shuffledword;

	void Privmsg(string msg) {
		return Send(("PRIVMSG " ~ channel ~ " :" ~ msg).idup);
	}

	void Send(string msg) {
		auto result = socket.send((msg ~ "\r\n").idup);
		writeln("<", msg);
		if(result == Socket.ERROR)
			throw new Exception("Socket send failed.");
	}
	
	void Disconnect() nothrow {
		connected = false;
		try {
			socket.shutdown(SocketShutdown.BOTH);
			socket.close();
		}
		catch(Exception e) {
		}
	}
public:
	this(Socket socket, dstring[] dictionary) nothrow {
		this.socket = socket;
		this.dictionary = dictionary;
	}
	
	bool Connected() const @property {
		return connected;
	}
	
	bool Connect(InternetAddress address, string nick, string channel) nothrow {
		this.channel = channel;
		try {
			socket.connect(address);
			socket.blocking = false;

			Send("NICK " ~ nick);
			Send("USER " ~ nick ~ " 0 * :anagram bot");
			Send("JOIN " ~ this.channel);
			connected = true;
		}
		catch(Exception e) {
			Disconnect();
			return false;
		}
		return true;
	}
	
	void Scramble() {
		ulong number = uniform(0, dictionary.length);
		currentword = dictionary[number].dup;
		shuffledword = dictionary[number].dup;
		randomShuffle(shuffledword);
		Privmsg("Unscramble: " ~ to!string(shuffledword));
		writeln("Word: " ~ to!string(currentword));
	}
	
	void Stop() {
		sw.stop();
		currentword = to!dstring("");
	}
	
	void Update() nothrow {
		try {
			if(sw.running && sw.peek().seconds > 30) {
				Privmsg("Time's up, the word was: " ~ to!string(currentword));
				if(inactivitysw.peek().seconds() > 600) {
					Privmsg("Ten minutes inactivity, stopping the game.");
					Stop();
				} else {
					Scramble();
				}
				sw.reset();
			}

			char[1024] buffer;
			auto received = socket.receive(buffer);
			if(received == Socket.ERROR) {
				return;
			}
			
			if(received == 0) {
				return;
			}
			
			auto receivebuffer = buffer[0 .. received];
			writeln(">", receivebuffer);
			
			if(startsWith(receivebuffer, "PING")) {
				receivebuffer[1] = 'O';
				Send(receivebuffer.dup);
			}
			
			auto nickend = indexOf(receivebuffer, "!");
			auto peerend = indexOf(receivebuffer, " ");
			if(nickend > -1 && startsWith(receivebuffer, ":") && nickend < peerend) {
				char[] nick;
				char[] peer;
				char[] command;
				char[] channel;
				char[] message;
				receivebuffer = stripRight(receivebuffer);
				nick = receivebuffer[1 .. nickend];
				peer = receivebuffer[nickend + 1 .. peerend];
				auto rbs = split(receivebuffer, ' ');
				command = rbs[1];
				channel = rbs[2];
				
				auto channelend = indexOf(receivebuffer, channel);
				if(channelend > -1 && channelend + channel.length + 2 < receivebuffer.length) {
					message = receivebuffer[channelend + channel.length + 2 .. $];
				}
				
				writefln("Nick: '%s'", nick);
				writefln("Peer: '%s'", peer);
				writefln("Command: '%s'", command);
				writefln("Channel: '%s'", channel);
				writefln("Message: '%s'", message);
				
				if(command == "PRIVMSG") {
					if(nick == "Trezker") {
						if(message == "!quit") {
							Privmsg("Shutting down");
							Disconnect();
							return;
						}
					}
					if(message == "!stop") {
						Privmsg("Stopping, use !start to play. The last word was: " ~ to!string(currentword));
						Stop();
					}
					if(message == "!start") {
						Scramble();
						sw.start();
						inactivitysw.start();
						inactivitysw.reset();
					}
					if(toLower(strip(message)) == toLower(to!string(currentword))) {
						Privmsg(nick.idup ~ " is correct: " ~ to!string(currentword));
						Scramble();
						sw.reset();
						inactivitysw.reset();
					}
				}
			}
		}
		catch(Exception e) {
			try {
				writeln("Exception!!!");
			}
			catch(Exception ee) {
			}
			Disconnect();
		}
	}
}
