import kilo;

import std.stdio: writeln;
import std;

extern(C)
void handleSigWinCh(int unused) {

    updateWindowSize();
    if (kilo.E.cy > kilo.E.screenrows) kilo.E.cy = kilo.E.screenrows - 1;
    if (kilo.E.cx > kilo.E.screencols) kilo.E.cx = kilo.E.screencols - 1;
    editorRefreshScreen();
}
void initEditor() {
    kilo.E.cx = 0;
    kilo.E.cy = 0;
    kilo.E.rowoff = 0;
    kilo.E.coloff = 0;
    kilo.E.numrows = 0;
    kilo.E.row = null;
    kilo.E.dirty = 0;
    kilo.E.filename = null;
    kilo.E.syntax = null;
    updateWindowSize();
    // dmd complains about the function being type void.
     extern(C) void function(int) han = &handleSigWinCh;
    // added 0 arg, dmd is more strict.
    signal(SIGWINCH, han); 
}
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
