%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Gorilla Combiner
% 1) Check condition folders (ms0, ms250, ms500, ms1100) and sequence 
%    subfolders (AXBY, BAYX, XYAB, YBXA). Missing folders are skipped.
% 2) For each sequence folder, load the 3 manually specified Excel files:
%    task, generalization, and questionnaire.
% 3) Combine the same file type across sequence folders and save in the
%    main condition folder with condition-specific names:
%    - combined_task_ms250.xlsx
%    - combined_generalization_ms250.xlsx
%    - combined_questionnaire_ms250.xlsx
%    etc.
% 4) Remove the last row if any cell in that row says "END OF FILE"
% 5) Remove rows belonging to incomplete participants based on
%    "Participant Private ID"
% 6) Keep original column names
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

rootFolder = "D:\Data\SMART";
conditionFolders = ["ms0","ms250", "ms500", "ms1100"];
sequenceFolders = ["AXBY", "BAYX", "XYAB", "YBXA"];

outNames = [
    "combined_task"
    "combined_generalization"
    "combined_questionnaire"
];

% 15682305, 15681711, 15682617, 15682794: Experiment incomplete (don't have generalization)
% 15769153, 15769343, 15844363, 15848040: More than 25% total trials removed
% 15769284, 15661417, 15854428, 15769347: More than 25% block 6 AND/OR 7 trials removed
% 15847577: Global accuracy below 75%
% 15848605, 15682014, 15681768, 15682007: Chaotic RT directional changes

excludedParticipantIDs = [
    "15682305"    
    "15681711"
    "15682617"
    "15682794"
    "15769153"
    "15769343"
    "15844363"
    "15848040"
    "15769284"
    "15661417"
    "15854428"
    "15769347"
    "15847577"
    "15848605"
    "15682014"
    "15681768"
    "15682007"
];

% excludedParticipantIDs = strings(0,1);
excludedParticipantIDs = string(excludedParticipantIDs);

manualFiles = struct();

manualFiles.ms0.AXBY = [
    "data_exp_268462-v4_task-uxgc.xlsx"
    "data_exp_268462-v4_task-c9jr.xlsx"
    "data_exp_268462-v4_questionnaire-dc2w.xlsx"
];

manualFiles.ms0.BAYX = [
    "data_exp_268465-v3_task-3de8.xlsx"
    "data_exp_268465-v3_task-ghdw.xlsx"
    "data_exp_268465-v3_questionnaire-dc2w.xlsx"
];

manualFiles.ms0.XYAB = [
    "data_exp_268466-v3_task-yd8z.xlsx"
    "data_exp_268466-v3_task-9a6q.xlsx"
    "data_exp_268466-v3_questionnaire-dc2w.xlsx"
];

manualFiles.ms0.YBXA = [
    "data_exp_268467-v3_task-trff.xlsx"
    "data_exp_268467-v3_task-3l6o.xlsx"
    "data_exp_268467-v3_questionnaire-dc2w.xlsx"
];

manualFiles.ms250.AXBY = [
    "data_exp_266295-vall_task-xfkr.xlsx"
    "data_exp_266295-vall_task-c9jr.xlsx"
    "data_exp_266295-vall_questionnaire-dc2w.xlsx"
];

manualFiles.ms250.BAYX = [
    "data_exp_267164-v5_task-3de8.xlsx"
    "data_exp_267164-v5_task-ghdw.xlsx"
    "data_exp_267164-v5_questionnaire-dc2w.xlsx"
];

manualFiles.ms250.XYAB = [
    "data_exp_267166-v5_task-yd8z.xlsx"
    "data_exp_267166-v5_task-9a6q.xlsx"
    "data_exp_267166-v5_questionnaire-dc2w.xlsx"
];

manualFiles.ms250.YBXA = [
    "data_exp_267168-v5_task-trff.xlsx"
    "data_exp_267168-v5_task-3l6o.xlsx"
    "data_exp_267168-v5_questionnaire-dc2w.xlsx"
];

manualFiles.ms500.AXBY = [
    "data_exp_266298-vall_task-m9je.xlsx"
    "data_exp_266298-vall_task-c9jr.xlsx"
    "data_exp_266298-vall_questionnaire-dc2w.xlsx"
];

manualFiles.ms500.BAYX = [
    "data_exp_267165-v5_task-rqe4.xlsx"
    "data_exp_267165-v5_task-ghdw.xlsx"
    "data_exp_267165-v5_questionnaire-dc2w.xlsx"
];

manualFiles.ms500.XYAB = [
    "data_exp_267167-v3_task-fybm.xlsx"
    "data_exp_267167-v3_task-9a6q.xlsx"
    "data_exp_267167-v3_questionnaire-dc2w.xlsx"
];

manualFiles.ms500.YBXA = [
    "data_exp_267169-v6_task-x3zw.xlsx"
    "data_exp_267169-v6_task-3l6o.xlsx"
    "data_exp_267169-v6_questionnaire-dc2w.xlsx"
];

manualFiles.ms1100.AXBY = [
    "data_exp_260699-vall_task-nf38.xlsx"
    "data_exp_260699-vall_task-c9jr.xlsx"
    "data_exp_260699-vall_questionnaire-dc2w.xlsx"
];

manualFiles.ms1100.BAYX = [
    "data_exp_260700-v10_task-v4q6.xlsx"
    "data_exp_260700-v10_task-ghdw.xlsx"
    "data_exp_260700-v10_questionnaire-dc2w.xlsx"
];

manualFiles.ms1100.XYAB = [
    "data_exp_260701-v8_task-j31i.xlsx"
    "data_exp_260701-v8_task-9a6q.xlsx"
    "data_exp_260701-v8_questionnaire-dc2w.xlsx"
];

manualFiles.ms1100.YBXA = [
    "data_exp_260704-v10_task-hgr6.xlsx"
    "data_exp_260704-v10_task-3l6o.xlsx"
    "data_exp_260704-v10_questionnaire-dc2w.xlsx"
];

for c = 1:numel(conditionFolders)

    condName = conditionFolders(c);
    condFolder = fullfile(rootFolder, condName);

    fprintf("\n====================================================\n");
    fprintf("Checking folder: %s\n", condFolder);

    if ~isfolder(condFolder)
        warning("Folder not found, skipping: %s", condFolder);
        continue;
    end

    combinedTables = cell(1, numel(outNames));
    firstFilePaths = strings(1, numel(outNames));
    hasData = false(1, numel(outNames));

    for s = 1:numel(sequenceFolders)

        seqName = sequenceFolders(s);
        seqFolder = fullfile(condFolder, seqName);

        if ~isfolder(seqFolder)
            fprintf("Skipping missing folder: %s\n", seqFolder);
            continue;
        end

        fprintf("\nProcessing sequence: %s\n", seqName);

        if ~isfield(manualFiles, condName) || ~isfield(manualFiles.(condName), seqName)
            error("Missing manual file list for %s / %s", condName, seqName);
        end

        theseFiles = string(manualFiles.(condName).(seqName));

        if numel(theseFiles) ~= numel(outNames)
            error("You must provide exactly %d filenames for %s / %s", numel(outNames), condName, seqName);
        end

        for k = 1:numel(outNames)

            thisFile = fullfile(seqFolder, theseFiles(k));

            if ~isfile(thisFile)
                error("File not found: %s", thisFile);
            end

            fprintf("  Reading: %s\n", thisFile);

            T = readtable(thisFile, ...
                "VariableNamingRule", "preserve", ...
                "TextType", "string");

            % Remove final END OF FILE row if present
            if height(T) >= 1
                lastRow = T{end, :};
                hasEndOfFile = false;

                for j = 1:numel(lastRow)
                    try
                        sval = string(lastRow(j));
                    catch
                        continue;
                    end

                    if any(strtrim(sval) == "END OF FILE")
                        hasEndOfFile = true;
                        break;
                    end
                end

                if hasEndOfFile
                    T(end,:) = [];
                    fprintf("    Removed final 'END OF FILE' row.\n");
                end
            end

            % Remove incomplete participants
            participantIDs = string(T.("Participant Private ID"));
            rowsToRemove = ismember(strtrim(string(participantIDs)), excludedParticipantIDs);
            nRemoved = sum(rowsToRemove);

            if nRemoved > 0
                T(rowsToRemove, :) = [];
                fprintf("    Removed %d rows from excluded participants.\n", nRemoved);
            else
                fprintf("    No excluded participants found in this file.\n");
            end

            % Combine tables
            if ~hasData(k)
                combinedTables{k} = T;
                firstFilePaths(k) = thisFile;
                hasData(k) = true;
            else
                if ~isequal(combinedTables{k}.Properties.VariableNames, T.Properties.VariableNames)
                    error("Column mismatch between files:\n%s\n%s", firstFilePaths(k), thisFile);
                end

                combinedTables{k} = [combinedTables{k}; T];
            end
        end
    end

    % Save outputs with condition-specific suffix
    for k = 1:numel(outNames)
        if hasData(k)
            outFileName = sprintf("%s_%s.xlsx", outNames(k), condName);
            outFile = fullfile(condFolder, outFileName);
            writetable(combinedTables{k}, outFile, "FileType", "spreadsheet");

            fprintf("\nSaved: %s\n", outFile);
            fprintf("Total rows written: %d\n", height(combinedTables{k}));
        else
            fprintf("\nNo data combined for output: %s_%s.xlsx\n", outNames(k), condName);
        end
    end
end

fprintf("\nAll done.\n");


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Organizer - First part
% 1) Search inside ms0, ms250, ms500, and ms1100 folders
% 2) In each folder, load combined_task.xlsx
% 3) Remove final "END OF FILE" row if present
% 4) Keep only rows where Zone Type == "response_keyboard_single"
% 5) Keep selected columns
% 6) Add a new column indicating SMART length
% 7) Combine everything into one SMART_Data_compressed.xlsx file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

rootFolder = "D:\Data\SMART";
conditionFolders = ["ms0", "ms250", "ms500", "ms1100"];
targetBaseName = "combined_task";
dataFolder = fullfile(rootFolder, "data");

if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

outFile = fullfile(dataFolder, "SMART_Data_compressed.xlsx");

zoneHeader = "Zone Type";

keepHeaders = [
    "Participant Private ID"
    "Reaction Time"
    "Response"
    "Correct Answer"
    "Correct"
    "category_type"
    "block"
];

Tall = table();

for c = 1:numel(conditionFolders)

    condName = conditionFolders(c);
    condFolder = fullfile(rootFolder, condName);

    if ~isfolder(condFolder)
        warning("Folder not found, skipping: %s", condFolder);
        continue;
    end

    targetFile = sprintf("%s_%s.xlsx", targetBaseName, condName);
    inFile = fullfile(condFolder, targetFile);

    if ~isfile(inFile)
        warning("Target file not found, skipping: %s", inFile);
        continue;
    end

    fprintf("\nProcessing folder: %s\n", condFolder);
    fprintf("Loading file: %s\n", inFile);

    T = readtable(inFile, "VariableNamingRule", "preserve", "TextType", "string");

    if height(T) >= 1
        lastRow = T{end, :};
        hasEndOfFile = false;

        for j = 1:numel(lastRow)
            try
                sval = string(lastRow(j));
            catch
                continue;
            end

            if any(strtrim(sval) == "END OF FILE")
                hasEndOfFile = true;
                break;
            end
        end

        if hasEndOfFile
            T(end, :) = [];
            fprintf("  Removed final 'END OF FILE' row.\n");
        end
    end

    findVar = @(hdr) localFindVarName(hdr, T);

    zoneVar = findVar(zoneHeader);

    keepVars = strings(numel(keepHeaders), 1);
    for i = 1:numel(keepHeaders)
        keepVars(i) = findVar(keepHeaders(i));
    end

    z = string(T.(zoneVar));
    rowMask = (z == "response_keyboard_single");

    Tout = T(rowMask, keepVars);
    Tout.Properties.VariableNames = matlab.lang.makeUniqueStrings(keepHeaders);

    fprintf("  Columns in Tout:\n");
    disp(Tout.Properties.VariableNames')
    
    pid_tmp = erase(string(Tout.("Participant Private ID")), "'");
    blk_tmp = str2double(erase(string(Tout.("block")), "'"));
    
    fprintf("  Unique participants in %s: %d\n", condName, numel(unique(pid_tmp)));
    fprintf("  Block count check BEFORE duplicate removal:\n");
    
    [Gtmp, pid_g, blk_g] = findgroups(pid_tmp, blk_tmp);
    nRows_g = splitapply(@numel, blk_tmp, Gtmp);
    
    checkTable = table(pid_g, blk_g, nRows_g, ...
        'VariableNames', {'ParticipantID','Block','N_rows'});
    
    disp(checkTable(checkTable.N_rows > 48,:))
    
    badParticipants = unique(checkTable.ParticipantID(checkTable.N_rows > 48));
    
    if ~isempty(badParticipants)
        fprintf("  Removing duplicated participants:\n");
        disp(badParticipants)
    
        Tout = Tout(~ismember(pid_tmp, badParticipants), :);
    
        fprintf("  Rows after duplicate-participant removal: %d\n", height(Tout));
    end

    smartLen = repmat(string(condName), height(Tout), 1);
    Tout = addvars(Tout, smartLen, 'After', 'Participant Private ID', ...
        'NewVariableNames', 'SMART_length');

    if isempty(Tall)
        Tall = Tout;
    else
        Tall = [Tall; Tout];
    end

    fprintf("  Kept rows: %d of %d\n", height(Tout), height(T));
end

if isfile(outFile)
    delete(outFile);
end

writetable(Tall, outFile, "FileType", "spreadsheet");

fprintf("\nOutput file: %s\n", outFile);
fprintf("Total rows written: %d\n", height(Tall));


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Organizer - Second part
% 1) Search inside ms0, ms250, ms500, and ms1100 folders
% 2) In each folder, load combined_generalization.xlsx
% 3) Remove final "END OF FILE" row if present
% 4) Keep only rows where Zone Type == "response_keyboard_single"
% 5) Keep selected columns
% 6) Add a new column indicating SMART length
% 7) Rename Category values: a/b -> uni, x/y -> multi
% 8) Combine everything into one Generalization_Data_compressed.xlsx file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

rootFolder = "D:\Data\SMART";
conditionFolders = ["ms0", "ms250", "ms500", "ms1100"];
targetBaseName = "combined_generalization";
dataFolder = fullfile(rootFolder, "data");

if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

outFile = fullfile(dataFolder, "Generalization_Data_compressed.xlsx");

zoneHeader = "Zone Type";

keepHeaders = [
    "Participant Private ID"
    "Reaction Time"
    "Response"
    "CorrectAnswer"
    "Correct"
    "Category"
];

Tall = table();

for c = 1:numel(conditionFolders)

    condName = conditionFolders(c);
    condFolder = fullfile(rootFolder, condName);

    if ~isfolder(condFolder)
        warning("Folder not found, skipping: %s", condFolder);
        continue;
    end

    targetFile = sprintf("%s_%s.xlsx", targetBaseName, condName);
    inFile = fullfile(condFolder, targetFile);

    if ~isfile(inFile)
        warning("Target file not found, skipping: %s", inFile);
        continue;
    end

    fprintf("\nProcessing folder: %s\n", condFolder);
    fprintf("Loading file: %s\n", inFile);

    T = readtable(inFile, "VariableNamingRule", "preserve", "TextType", "string");

    if height(T) >= 1
        lastRow = T{end, :};
        hasEndOfFile = false;

        for j = 1:numel(lastRow)
            try
                sval = string(lastRow(j));
            catch
                continue;
            end

            if any(strtrim(sval) == "END OF FILE")
                hasEndOfFile = true;
                break;
            end
        end

        if hasEndOfFile
            T(end, :) = [];
            fprintf("  Removed final 'END OF FILE' row.\n");
        end
    end

    findVar = @(hdr) localFindVarName(hdr, T);

    zoneVar = findVar(zoneHeader);

    keepVars = strings(numel(keepHeaders), 1);
    for i = 1:numel(keepHeaders)
        keepVars(i) = findVar(keepHeaders(i));
    end

    z = string(T.(zoneVar));
    rowMask = (z == "response_keyboard_single");

    Tout = T(rowMask, keepVars);
    Tout.Properties.VariableNames = matlab.lang.makeUniqueStrings(keepHeaders);

    % Duplicate/repeated attempt diagnostic for Generalization
    pid_tmp = erase(string(Tout.("Participant Private ID")), "'");
    
    [Gtmp, pid_g] = findgroups(pid_tmp);
    nRows_g = splitapply(@numel, pid_tmp, Gtmp);
    
    checkTable = table(pid_g, nRows_g, ...
        'VariableNames', {'ParticipantID','N_rows'});
    
    badParticipants = unique(checkTable.ParticipantID(checkTable.N_rows > 48));
    
    if ~isempty(badParticipants)
        fprintf("  Removing duplicated Generalization participants:\n");
        disp(badParticipants)
    
        Tout = Tout(~ismember(pid_tmp, badParticipants), :);
    end

    smartLen = repmat({char(condName)}, height(Tout), 1);
    Tout = addvars(Tout, smartLen, 'After', 'Participant Private ID', ...
        'NewVariableNames', 'SMART_length');

    cat = string(Tout.Category);
    cat(cat == "a" | cat == "b") = "uni";
    cat(cat == "x" | cat == "y") = "multi";
    Tout.Category = cat;

    if isempty(Tall)
        Tall = Tout;
    else
        Tall = [Tall; Tout];
    end

    fprintf("  Kept rows: %d of %d\n", height(Tout), height(T));
end

if isfile(outFile)
    delete(outFile);
end

writetable(Tall, outFile, "FileType", "spreadsheet");

fprintf("\nOutput file: %s\n", outFile);
fprintf("Total rows written: %d\n", height(Tall));



%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Organizer - Third part
% 1) Search inside ms0, ms250, ms500, and ms1100 folders
% 2) In each folder, load combined_questionnaire.xlsx
% 3) Remove final "END OF FILE" row if present
% 4) Keep only selected demographic questions
% 5) Keep only: Participant Private ID, Question Key, Response
% 6) Add a new column indicating SMART length
% 7) Combine everything into one Demographics_Data_compressed.xlsx file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

rootFolder = "D:\Data\SMART";
conditionFolders = ["ms0", "ms250", "ms500", "ms1100"];
targetBaseName = "combined_questionnaire";
dataFolder = fullfile(rootFolder, "data");

if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

outFile = fullfile(dataFolder, "Demographics_Data_compressed.xlsx");

keepHeaders = [
    "Participant Private ID"
    "Question Key"
    "Response"
];

qKeep = [
    "age-question"
    "languages-question"
    "ethnicity-question"
    "race-question"
    "gender-question"
];

Tall = table();

for c = 1:numel(conditionFolders)

    condName = conditionFolders(c);
    condFolder = fullfile(rootFolder, condName);

    if ~isfolder(condFolder)
        warning("Folder not found, skipping: %s", condFolder);
        continue;
    end

    targetFile = sprintf("%s_%s.xlsx", targetBaseName, condName);
    inFile = fullfile(condFolder, targetFile);

    if ~isfile(inFile)
        warning("Target file not found, skipping: %s", inFile);
        continue;
    end

    fprintf("\nProcessing folder: %s\n", condFolder);
    fprintf("Loading file: %s\n", inFile);

    T = readtable(inFile, "VariableNamingRule", "preserve", "TextType", "string");

    if height(T) >= 1
        lastRow = T{end, :};
        hasEndOfFile = false;

        for j = 1:numel(lastRow)
            try
                sval = string(lastRow(j));
            catch
                continue;
            end

            if any(strtrim(sval) == "END OF FILE")
                hasEndOfFile = true;
                break;
            end
        end

        if hasEndOfFile
            T(end, :) = [];
            fprintf("  Removed final 'END OF FILE' row.\n");
        end
    end

    findVar = @(hdr) localFindVarName_2(hdr, T);

    idVar   = findVar("Participant Private ID");
    qkVar   = findVar("Question Key");
    respVar = findVar("Response");

    qk = strtrim(string(T.(qkVar)));
    rowMask = ismember(qk, qKeep);

    Tout = T(rowMask, [idVar, qkVar, respVar]);
    Tout.Properties.VariableNames = matlab.lang.makeUniqueStrings(keepHeaders);

    % Duplicate/repeated questionnaire diagnostic
    pid_tmp = erase(string(Tout.("Participant Private ID")), "'");
    
    [Gtmp, pid_g] = findgroups(pid_tmp);
    nRows_g = splitapply(@numel, pid_tmp, Gtmp);
    
    checkTable = table(pid_g, nRows_g, ...
        'VariableNames', {'ParticipantID','N_rows'});
    
    badParticipants = unique(checkTable.ParticipantID(checkTable.N_rows > numel(qKeep)));
    
    if ~isempty(badParticipants)
        fprintf("  Removing duplicated Demographics participants:\n");
        disp(badParticipants)
    
        Tout = Tout(~ismember(pid_tmp, badParticipants), :);
    end

    smartLen = repmat({char(condName)}, height(Tout), 1);
    Tout = addvars(Tout, smartLen, 'After', 'Participant Private ID', ...
        'NewVariableNames', 'SMART_length');

    if isempty(Tall)
        Tall = Tout;
    else
        Tall = [Tall; Tout];
    end

    fprintf("  Kept rows: %d of %d\n", height(Tout), height(T));
end

if isfile(outFile)
    delete(outFile);
end

writetable(Tall, outFile, "FileType", "spreadsheet");

fprintf("\nOutput file: %s\n", outFile);
fprintf("Total rows written: %d\n", height(Tall));



%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
function varName = localFindVarName(header, T)
    header = string(header);
    vnames = string(T.Properties.VariableNames);

    % 1) Exact match on VariableNames 
    idx = find(vnames == header, 1);
    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    % 2) Match against VariableDescriptions
    vdesc = string(T.Properties.VariableDescriptions);
    if ~isempty(vdesc)
        idx = find(vdesc == header, 1);
        if ~isempty(idx)
            varName = vnames(idx);
            return;
        end
    end

    % 3) Sanitized match (spaces -> underscores)
    sanitized = string(matlab.lang.makeValidName(header));
    idx = find(vnames == sanitized, 1);
    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    % 4) Relaxed match (ignore spaces/underscores/case)
    canon = @(s) lower(regexprep(string(s), "[\s_]+", ""));
    h = canon(header);
    idx = find(arrayfun(@(k) canon(vnames(k)) == h, 1:numel(vnames)), 1);

    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    % If still not found, show available headers
    error("Could not find column '%s'. Imported variable names include:\n%s", ...
        header, strjoin(vnames, ", "));
end


function varName = localFindVarName_2(header, T)
    header = string(header);
    vnames = string(T.Properties.VariableNames);

    % 1) Exact match on VariableNames (if preserved)
    idx = find(vnames == header, 1);
    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    % 2) Sanitized match (spaces -> underscores etc.)
    sanitized = string(matlab.lang.makeValidName(header));
    idx = find(vnames == sanitized, 1);
    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    % 3) Relaxed match (ignore spaces/underscores/case)
    canon = @(s) lower(regexprep(string(s), "[\s_]+", ""));
    h = canon(header);
    idx = find(arrayfun(@(k) canon(vnames(k)) == h, 1:numel(vnames)), 1);
    if ~isempty(idx)
        varName = vnames(idx);
        return;
    end

    error("Could not find column '%s'. Imported variable names include:\n%s", ...
        header, strjoin(vnames, ", "));
end