import std.socket;
import std.stdio;
import std.datetime;
import std.conv;
import std.random;
import std.string;
import std.algorithm;
import std.json;
import std.file;

/*TODO: Hints. 3 hints. 1 character per hint per 5 characters in word.
 * 	20% 30% 40% of remaining hidden characters
 *  1 _
 *  2 _ _
 *  3 _ _ 3
 *  4 _ _ 3 2
 *  5 _ _ 3 2 1
 *  6 _ _ _ 3 2 1
 *  7 _ _ _ 3 3 2 1
 *  8 _ _ _ 3 3 2 2 1
 *  9 _ _ _ _ 3 3 2 2 1
 * 10 _ _ _ _ 3 3 2 2 1 1
 * 11 _ _ _ _ _ 3 3 2 2 1 1
 * 12 _ _ _ _ _ 3 3 2 2 2 1 1
 * 
 * Points for other anagrams
 * Create a lookup dictionary matching the sorted character set to all words containing those characters.
 * Award 1 point for each word in that list.
 * 
 * Persistent storage of scores and settings.
 * http://dlang.org/phobos/std_json.html
 * 
 * Connection
 * 	server
 * 	port
 * 	nick
 * 	channel
 * Question timeout
 * Inactivity timeout
 * Score
 * 	Name
 * 	Points
*/

class Bot {
private:
	Socket socket;
	bool connected = false;
	bool exit = false;
	string channel;
	InternetAddress address;
	string nick;
	dstring[] dictionary;
	StopWatch inactivitysw;
	StopWatch sw;
	dchar[] currentword;
	dchar[] shuffledword;
	dchar[] hint;
	bool hints_enabled = false;
	int hintlevel = 0;
	int hintcount = 0;
	int[string] score;

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

	bool Exit() const @property {
		return exit;
	}
	
	bool Connect(InternetAddress address, string nick, string channel) nothrow {
		this.channel = channel;
		this.address = address;
		this.nick = nick;
		try {
			if(exists("scores.json")) {
				string json = readText("scores.json");
				
				writeln(json);
				JSONValue[string] document = parseJSON(json).object;
				JSONValue[] scores = document["scores"].array;

				foreach (scoreJson; scores) {
					JSONValue[string] s = scoreJson.object;

					string name = s["nick"].str;
					int points = to!int(s["score"].integer);

					score[name] = points;
					//writeln("Constructed: ", e);
				}
    		}
			
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
		hintlevel = 0;
		hintcount = 0;
		ulong number = uniform(0, dictionary.length);
		currentword = dictionary[number].dup;
		shuffledword = dictionary[number].dup;
		randomShuffle(shuffledword);
		hint.length = currentword.length;
		for(int i = 0; i < currentword.length; ++i) {
			hint[i] = to!dchar('_');
		}
		Privmsg("Unscramble: " ~ to!string(shuffledword));
		writeln("Word: " ~ to!string(currentword));
	}
	
	void Reveal(ulong n) {
		for(int i = 0; i < n; ++i) {
			ulong p = uniform(0, currentword.length - hintcount);
			while(hint[p] != '_')
				++p;
			hint[p] = currentword[p];
			++hintcount;
		}
	}
	
	void Stop() {
		sw.stop();
		currentword = [];
	}
	
	void Update() nothrow {
		try {
			if(hints_enabled) {
				if(hintlevel == 0 && sw.running && sw.peek().seconds > 10) {
					int numreveal = to!int(currentword.length * 0.2);
					++hintlevel;
					Reveal(numreveal);
					Privmsg("Hint 1: " ~ to!string(hint));
				}
				if(hintlevel == 1 && sw.running && sw.peek().seconds > 20) {
					++hintlevel;
					int numreveal = to!int((currentword.length-hintcount) * 0.3);
					Reveal(numreveal);
					Privmsg("Hint 2: " ~ to!string(hint));
				}
				if(hintlevel == 2 && sw.running && sw.peek().seconds > 30) {
					++hintlevel;
					int numreveal = to!int((currentword.length-hintcount) * 0.4);
					Reveal(numreveal);
					Privmsg("Hint 3: " ~ to!string(hint));
				}
			}
			if(sw.running && sw.peek().seconds > 40) {
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
				
				if(command == "QUIT" && nick == this.nick) {
					Disconnect();
				}
				else if(command == "PRIVMSG") {
					if(nick == "Trezker") {
						if(message == "!quit") {
							Privmsg("Shutting down");
							Disconnect();
							exit = true;
							return;
						}
					}
					if(message == "!help") {
						Privmsg("Available commands: !start, !stop, !hints on, !hints off");
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
					if(message == "!hints on") {
						hints_enabled = true;
						Privmsg("Hints are enabled");
					}
					if(message == "!hints off") {
						hints_enabled = false;
						Privmsg("Hints are disabled");
					}
					if(toLower(strip(message)) == toLower(to!string(currentword))) {
						score[nick.idup]++;
						Privmsg(nick.idup ~ " is correct: " ~ to!string(currentword));

						string[] sortedscore = score.keys;
						sort!((a,b) {return score[a] > score[b];})(sortedscore);
						
						char[] doc = "{\"scores\":[".dup;
						foreach(i, name; sortedscore) {
							if(i>0)
								doc ~= ",";
							JSONValue sc = parseJSON("{}");
							sc.object["nick"] = name;
							sc.object["score"] = score[sortedscore[i]];
							doc ~= toJSON(&sc);
						}
						doc ~= "]}";
						auto docjson = parseJSON(doc.idup);
						string docstr = toJSON(&docjson, true); 
						File file = File("scores.json", "w");
						file.write(docstr);

						char[] top;
						ulong start = 0;

						foreach(i, name; sortedscore) {
							if(name == nick.idup) {
								if(i > 3)
									start = i - 2;
								break;
							}
						}						
						
						for(ulong i = start; i < start+5; ++i) {
							if(i >= sortedscore.length)
								break;
							string pos;
							if(i == 0)
								pos = "1st";
							else if(i == 1)
								pos = "2nd";
							else if(i == 2)
								pos = "3rd";
							else
								pos = to!string(i+1) ~ "th";
							top ~= pos ~ ": " ~ sortedscore[i] ~ "(" ~ to!string(score[sortedscore[i]]) ~ ") ";
							//writefln("%s -> %s", sortedscore, score[sortedscore]);
						}
						Privmsg(("Rankings: " ~ top).idup);
						

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
				writeln(e.msg);
			}
			catch(Exception ee) {
			}
			Disconnect();
		}
	}
}
