import kilo;

import std.stdio: writeln;
import std;


int main(string[] args) {
    if(args.length != 2) {
        writeln(std.stdio.stderr, "Usage: dilo <filename>");
        // exit is imported from kilo, wich imports stdlib.h
        exit(1);
    }
    // append null terminator to 2nd arg
    // make it compatible with C code.
    char[] filename = cast(char[]) (args[1] ~ '\0');

    initEditor();
    editorSelectSyntaxHighlight(filename.ptr);
    editorOpen(filename.ptr);
    enableRawMode(STDIN_FILENO);

    char[] msg = "HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find".dup;
    editorSetStatusMessage(msg.ptr);

    while(true) {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }
        
    return 0;
}
