function root = project_root()
%PROJECT_ROOT Absolute path to the project root, wherever it is installed.
%
%   Every source file lives under src/, so the root is two levels above
%   src/common. Anything that needs data/ or output/ resolves through here
%   rather than guessing from its own location, which is what broke when
%   files moved during the refactor.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
