import std.stdio;


auto sTC(len: int, strs ...)() {

    char*[len] result;
    
    for(int i = 0; i < len - 1; i++) {

       strs[i] ~= '\0';
       result[i] = strs[i].ptr;
    }
}


string[] FOO = [".c", ".h", null];


void main() {

    writeln(FOO);
    
} 
