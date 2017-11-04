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

class Message {
	char[] nick;
	char[] peer;
	char[] command;
	char[] channel;
	char[] message;
}

class Bot {
private:
	Socket socket;
	bool connected = false;
	bool exit = false;
	string channel;
	InternetAddress address;
	string nick;
	dstring[] dictionary;
	StopWatch inactivityStopWatch;
	StopWatch stopWatch;
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
	

	void Update() nothrow {
		try {
			ShowHintsIfEnabled();
			StopIfTimeLimitReached();

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
			RespondToPing(receivebuffer);
			
			Message message = ParseMessage(receivebuffer);
			if(message !is null) {
				DisconnectIfBotQuits(message);
				HandleMessage(message);
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

	Message ParseMessage(char[] receivebuffer) {
		auto nickend = indexOf(receivebuffer, "!");
		auto peerend = indexOf(receivebuffer, " ");
		if(nickend > -1 && startsWith(receivebuffer, ":") && nickend < peerend) {
			Message message = new Message;
			receivebuffer = stripRight(receivebuffer);
			message.nick = receivebuffer[1 .. nickend];
			message.peer = receivebuffer[nickend + 1 .. peerend];
			auto rbs = split(receivebuffer, ' ');
			message.command = rbs[1];
			message.channel = rbs[2];
			
			auto channelend = indexOf(receivebuffer, channel);
			if(channelend > -1 && channelend + channel.length + 2 < receivebuffer.length) {
				message.message = receivebuffer[channelend + channel.length + 2 .. $];
			}
			
			writefln("Nick: '%s'", message.nick);
			writefln("Peer: '%s'", message.peer);
			writefln("Command: '%s'", message.command);
			writefln("Channel: '%s'", message.channel);
			writefln("Message: '%s'", message.message);
			return message;
		}
		return null;
	}
	
	void DisconnectIfBotQuits(Message message) {
		if(message.command == "QUIT" && message.nick == this.nick) {
			Disconnect();
		}
	}

	void HandleMessage(Message message) {
		if(message.command == "PRIVMSG") {
			if(message.nick == "Trezker") {
				if(message.message == "!quit") {
					Privmsg("Shutting down");
					Disconnect();
					exit = true;
					return;
				}
			}
			if(message.message == "!help") {
				Privmsg("Available commands: !start, !stop, !hints on, !hints off");
			}
			if(message.message == "!stop") {
				Privmsg("Stopping, use !start to play. The last word was: " ~ to!string(currentword));
				Stop();
			}
			if(message.message == "!start") {
				Scramble();
				stopWatch.start();
				inactivityStopWatch.start();
				inactivityStopWatch.reset();
			}
			if(message.message == "!hints on") {
				hints_enabled = true;
				Privmsg("Hints are enabled");
			}
			if(message.message == "!hints off") {
				hints_enabled = false;
				Privmsg("Hints are disabled");
			}
			if(toLower(strip(message.message)) == toLower(to!string(currentword))) {
				score[message.nick.idup]++;
				Privmsg(message.nick.idup ~ " is correct: " ~ to!string(currentword));

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
					if(name == message.nick.idup) {
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
				stopWatch.reset();
				inactivityStopWatch.reset();
			}
		}
	}
	
	void ShowHintsIfEnabled() {
		if(hints_enabled) {
			if(hintlevel == 0 && stopWatch.running && stopWatch.peek().seconds > 10) {
				int numreveal = to!int(currentword.length * 0.2);
				++hintlevel;
				Reveal(numreveal);
				Privmsg("Hint 1: " ~ to!string(hint));
			}
			if(hintlevel == 1 && stopWatch.running && stopWatch.peek().seconds > 20) {
				++hintlevel;
				int numreveal = to!int((currentword.length-hintcount) * 0.3);
				Reveal(numreveal);
				Privmsg("Hint 2: " ~ to!string(hint));
			}
			if(hintlevel == 2 && stopWatch.running && stopWatch.peek().seconds > 30) {
				++hintlevel;
				int numreveal = to!int((currentword.length-hintcount) * 0.4);
				Reveal(numreveal);
				Privmsg("Hint 3: " ~ to!string(hint));
			}
		}
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

	void StopIfTimeLimitReached() {
		if(stopWatch.running && stopWatch.peek().seconds > 40) {
			Privmsg("Time's up, the word was: " ~ to!string(currentword));
			if(inactivityStopWatch.peek().seconds() > 600) {
				Privmsg("Ten minutes inactivity, stopping the game.");
				Stop();
			} else {
				Scramble();
			}
			stopWatch.reset();
		}
	}

	void Stop() {
		stopWatch.stop();
		currentword = [];
	}

	void RespondToPing(char[] receivebuffer) {
		if(startsWith(receivebuffer, "PING")) {
			receivebuffer[1] = 'O';
			Send(receivebuffer.dup);
		}
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
}
