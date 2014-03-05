import std.stdio;
import std.algorithm;
import std.string;
import std.conv;
import core.thread;
import std.socket;

import bot;

dstring[] Load_dictionary() {
	writeln("Loading dictionary from '/usr/share/dict/words'");
	auto f = File("/usr/share/dict/words");
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
	dstring[] dict = Load_dictionary();

	Bot bot = new Bot(new TcpSocket(), Load_dictionary);
	bot.Connect(new InternetAddress("irc.freenode.net", 6667), "ragaman-test", "##anagramtest");
	
	while(bot.Connected) {
		Thread.sleep( dur!("msecs")( 50 ) );
		bot.Update();
	}
}
