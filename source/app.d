import std.stdio;
import std.algorithm;
import std.string;
import std.conv;
import core.thread;
import std.socket;
import std.json;

import bot;

dstring[] Load_dictionary() {
	writeln("Loading dictionary from '/usr/share/dict/words'");
	//auto f = File("/usr/share/dict/words");
	auto f = File("words");
	scope(exit) f.close();
	dstring[] lines;

	foreach (str; f.byLine) {
		if(indexOf(str.idup, "'") > -1)
			continue;
		lines ~= to!dstring(str.idup);
	}

	return lines;
}

void main() {
	//Try to load connection settings from file
	//Otherwise generate that file
	JSONValue connection = parseJSON("{}");
	connection.object["nick"] = "test";
	connection.object["port"] = 6667;
	JSONValue root = parseJSON("{}");
	root.object["connection"] = connection;
	writeln(toJSON(&root));
	
	//Try to load game state from file
	//Otherwise provide default state object to the bot
	//The state object should have a save method so the bot can refresh the state on disk as changes occur.
	
	dstring[] dict = Load_dictionary();

	Bot bot = new Bot(new TcpSocket(), dict);
	while(!bot.Exit) {
		while(!bot.Connected) {
			try {
				bot = new Bot(new TcpSocket(), dict);
				auto address = new InternetAddress("irc.freenode.net", 6667);
				bot.Connect(address, "ragaman", "##anagram");
			}
			catch(Exception e) {
				writeln(e.msg);
				Thread.sleep( dur!("msecs")( 5000 ) );
			}
		}
		Thread.sleep( dur!("msecs")( 50 ) );
		bot.Update();
	}
}
