import kilo;

import std.stdio : writeln;
import std;

// resolve conflicts between libc and core.stdc.
// we prefer D's version, more type safety.
alias libc = core.stdc;
alias cio = libc.stdio;
/* making clear that kilo namespace is used
 to resolve conflicts between symbols built in C
  and D's reimport of those symbols in core.* */
alias cbuiltin = kilo;

// dmd is not able to handle the errno macro
// so just pulled up the original name in
// glibc. probably not portable.
alias diloErrno = __errno_location;

/* Raw mode: 1960 magic shit. */
int enableRawMode(int fd)
{
    termios raw;
    if (kilo.E.rawmode)
        return 0; /* Already enabled. */

    bool err = true;
    // replaced 'goto fatal' with scope(exit)
    scope (exit)
        if (err) *diloErrno() = ENOTTY;
    
    if (!isatty(STDIN_FILENO))
        return -1;

    atexit(&editorAtExit);
    if (tcgetattr(fd, &orig_termios) == -1)
        return -1;

    raw = orig_termios; /* modify the original mode */
    /* input modes: no break, no CR to NL, no parity check, no strip char,
     * no start/stop output control. */
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    /* output modes - disable post processing */
    raw.c_oflag &= ~(OPOST);
    /* control modes - set 8 bit chars */
    raw.c_cflag |= (CS8);
    /* local modes - choing off, canonical off, no extended functions,
     * no signal chars (^Z,^C) */
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    /* control chars - set return condition: min number of bytes and timer. */
    raw.c_cc[VMIN] = 0; /* Return each byte, or zero for timeout. */
    raw.c_cc[VTIME] = 1; /* 100 ms timeout (unit is tens of second). */

    /* put terminal in raw mode after flushing */
    if (tcsetattr(fd, TCSAFLUSH, &raw) < 0)
        return -1;
        
    kilo.E.rawmode = 1;
    // no error, set to false so that scope(exit)
    // dont modify errno
    err = false;
    return 0;
}

/* Load the specified program in the editor memory and returns 0 on success
 * or 1 on error. */
int editorOpen(char* filename)
{
    cio.FILE* fp;

    kilo.E.dirty = 0;
    free(kilo.E.filename);
    size_t fnlen = strlen(filename) + 1;
    kilo.E.filename = cast(char*) malloc(fnlen);
    memcpy(kilo.E.filename, filename, fnlen);

    fp = cio.fopen(filename, "r");
    if (!fp)
    {
        if (errno != ENOENT)
        {
            cio.perror("Opening file");
            exit(1);
        }
        return 1;
    }

    char* line = null;
    size_t linecap = 0;
    cbuiltin.ssize_t linelen;
    // cast away the shared in fp.
    while ((linelen = getline(&line, &linecap, cast(cbuiltin._IO_FILE*) fp)) != -1)
    {
        if (linelen && (line[linelen - 1] == '\n' || line[linelen - 1] == '\r'))
            line[--linelen] = '\0';
        editorInsertRow(kilo.E.numrows, line, linelen);
    }
    free(line);
    fclose(fp);
    kilo.E.dirty = 0;
    return 0;
}

/* Select the syntax highlight scheme depending on the filename,
 * setting it in the global state E.syntax. */
void editorSelectSyntaxHighlight(const char* filename)
{
    for (size_t j = 0; j < HLDB_ENTRIES; j++)
    {
        editorSyntax* s = &HLDB[j];
        size_t i = 0;
        while (s.filematch[i])
        {
            char* p;
            size_t patlen = strlen(s.filematch[i]);
            if ((p = strstr(filename, s.filematch[i])) != NULL)
            {
                if (s.filematch[i][0] != '.' || p[patlen] == '\0')
                {
                    kilo.E.syntax = s;
                    return;
                }
            }
            i++;
        }
    }
}

extern (C)
void handleSigWinCh(int unused)
{

    updateWindowSize();
    if (kilo.E.cy > kilo.E.screenrows)
        kilo.E.cy = kilo.E.screenrows - 1;
    if (kilo.E.cx > kilo.E.screencols)
        kilo.E.cx = kilo.E.screencols - 1;
    editorRefreshScreen();
}

void initEditor()
{
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
    signal(SIGWINCH, &handleSigWinCh);
}

int main(string[] args)
{
    if (args.length != 2)
    {
        writeln(std.stdio.stderr, "Usage: dilo <filename>");
        // exit is imported from kilo, wich imports stdlib.h
        exit(1);
    }
    // append null terminator to 2nd arg
    // make it compatible with C code.
    char[] filename = cast(char[])(args[1] ~ '\0');

    initEditor();
    editorSelectSyntaxHighlight(filename.ptr);
    editorOpen(filename.ptr);
    enableRawMode(STDIN_FILENO);

    char[] msg = "HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find".dup;
    editorSetStatusMessage(msg.ptr);

    while (true)
    {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }

    return 0;
}
