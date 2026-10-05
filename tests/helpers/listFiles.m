function names = listFiles(folder)
%listFiles - Return the names of the files in a folder in sorted order
%   NAMES = listFiles(FOLDER) returns a string array with the names of
%   the files in FOLDER, without subfolders. The names are sorted, so
%   that a test can compare them with an expected list.

    listing = dir(folder);
    names = sort(string({listing(~[listing.isdir]).name}));
end
