clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");

if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Part 0 (Preprocessing & Participant Quality Check)
% 1) Load SMART, Generalization, and Demographics data
%    - (Already discarded) Failed headphone validation / catch trials
%    - (Already discarded) Incomplete dataset / participant did not finish task
% 2) Apply participant-level exclusion criteria (Step 1):
%    - Remove participants with global SMART accuracy <=75%
% 3) Apply SMART trial-level filter:
%    - Keep correct SMART trials only (Correct == 1)
%    - Keep SMART trials within RT boundaries (100 ms > RT < 1500 ms)
% 4) Apply post-filter exclusion criteria (Step 2):
%    - Remove participants with <=75% usable SMART trials globally after filtering
%    - Remove participants with <=75% usable SMART trials in Block 6 after filtering
%    - Remove participants with <=75% usable SMART trials in Block 7 after filtering
%    - 2 or more meaningful RT direction changes across blocks 1–6 (>100 ms)
%    - At least one pair of consecutive large RT jumps in the same direction across blocks 1–6 (>100 ms each)
% 5) Save preprocessed datasets
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
dataDir = fullfile(baseDir, "data");
resultsDir = fullfile(baseDir, "results");

smartFile = fullfile(dataDir, "SMART_Data_compressed.xlsx");
genFile   = fullfile(dataDir, "Generalization_Data_compressed.xlsx");
demoFile  = fullfile(dataDir, "Demographics_Data_compressed.xlsx");

smartOut = fullfile(dataDir, "SMART_Data_compressed_preprocessed.xlsx");
genOut   = fullfile(dataDir, "Generalization_Data_compressed_preprocessed.xlsx");
demoOut  = fullfile(dataDir, "Demographics_Data_compressed_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "0_Participant_Preprocessing_QC.txt");

% Step 1 — Load data
Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

hasDemo = isfile(demoFile);
if hasDemo
    Td = readtable(demoFile, "VariableNamingRule","preserve", "TextType","string");
end

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Correct = str2double(erase(string(Ts.("Correct")), "'"));
Participant = erase(string(Ts.("Participant Private ID")), "'");
SMART_length = string(Ts.("SMART_length"));

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
Correct_g = str2double(erase(string(Tg.("Correct")), "'"));
Category_g = lower(strtrim(erase(string(Tg.("Category")), "'")));

if hasDemo
    Participant_d = erase(string(Td.("Participant Private ID")), "'");
end

conditions = ["ms0","ms250","ms500","ms1100"];
stabilityBlocks = 1:6;

% Prepare participant-level metrics
participants = unique(Participant);
nP = numel(participants);

smart_len = strings(nP,1);
globalAcc = NaN(nP,1);
meanRT_raw_valid = NaN(nP,1);

pct_fast = NaN(nP,1);
pct_slow = NaN(nP,1);
pct_removed = NaN(nP,1);

b6_total = NaN(nP,1);
b6_removed = NaN(nP,1);
b6_pct_removed = NaN(nP,1);

b7_total = NaN(nP,1);
b7_removed = NaN(nP,1);
b7_pct_removed = NaN(nP,1);

genMean = NaN(nP,1);

for i = 1:nP

    pid = participants(i);
    idx = Participant == pid;

    rt_i = RT(idx);
    block_i = Block(idx);
    correct_i = Correct(idx);
    smart_len(i) = SMART_length(find(idx,1));

    globalAcc(i) = mean(correct_i == 1, "omitnan") * 100;

    validRT_i = rt_i > 100 & rt_i < 1500;
    meanRT_raw_valid(i) = mean(rt_i(validRT_i), "omitnan");

    n_total = numel(rt_i);
    n_fast = sum(rt_i <= 100);
    n_slow = sum(rt_i >= 1500);

    pct_fast(i) = (n_fast / n_total) * 100;
    pct_slow(i) = (n_slow / n_total) * 100;
    pct_removed(i) = ((n_fast + n_slow) / n_total) * 100;

    idx_b6 = block_i == 6;
    rt_b6 = rt_i(idx_b6);
    b6_total(i) = numel(rt_b6);
    b6_removed(i) = sum(rt_b6 <= 100 | rt_b6 >= 1500);
    b6_pct_removed(i) = (b6_removed(i) / b6_total(i)) * 100;

    idx_b7 = block_i == 7;
    rt_b7 = rt_i(idx_b7);
    b7_total(i) = numel(rt_b7);
    b7_removed(i) = sum(rt_b7 <= 100 | rt_b7 >= 1500);
    b7_pct_removed(i) = (b7_removed(i) / b7_total(i)) * 100;

    idx_g = Participant_g == pid;
    if any(idx_g)
        correct_g_i = Correct_g(idx_g);
        category_g_i = Category_g(idx_g);

        uni = mean(correct_g_i(category_g_i == "uni") == 1, "omitnan");
        multi = mean(correct_g_i(category_g_i == "multi") == 1, "omitnan");

        genMean(i) = mean([uni, multi], "omitnan") * 100;
    end
end

M = table(participants, smart_len, globalAcc, meanRT_raw_valid, genMean, ...
    pct_fast, pct_slow, pct_removed, ...
    b6_total, b6_removed, b6_pct_removed, ...
    b7_total, b7_removed, b7_pct_removed, ...
    'VariableNames', {'ParticipantID','SMART_length','GlobalAccuracy','MeanRT_ValidRaw','GenMean', ...
    'PctFast','PctSlow','PctRemoved', ...
    'B6_Total','B6_Removed','B6_PctRemoved', ...
    'B7_Total','B7_Removed','B7_PctRemoved'});

% Step 2 — Apply participant-level exclusion criteria
M.ExcludeStep1 = false(height(M),1);
M.Step1Reason = strings(height(M),1);

for i = 1:height(M)

    reasons = strings(0,1);

    if M.GlobalAccuracy(i) <= 75
        reasons(end+1) = "Global SMART accuracy <=75%";
    end

    if ~isempty(reasons)
        M.ExcludeStep1(i) = true;
        M.Step1Reason(i) = strjoin(reasons, "; ");
    end
end

step1Excluded = M.ParticipantID(M.ExcludeStep1);
step1Keep = ~ismember(Participant, step1Excluded);

Ts_step1 = Ts(step1Keep,:);
RT_step1 = RT(step1Keep);
Block_step1 = Block(step1Keep);
Correct_step1 = Correct(step1Keep);
Participant_step1 = Participant(step1Keep);
SMART_step1 = SMART_length(step1Keep);

% Step 3 — Apply SMART trial-level filter
validSmartTrial = Correct_step1 == 1 & RT_step1 > 100 & RT_step1 < 1500;

Ts_filtered = Ts_step1(validSmartTrial,:);

Participant_filtered = Participant_step1(validSmartTrial);
Block_filtered = Block_step1(validSmartTrial);
RT_filtered = RT_step1(validSmartTrial);
SMART_filtered = SMART_step1(validSmartTrial);

% Step 4 — Apply post-filter exclusion criteria
M.Step2_UsableGlobalPct = NaN(height(M),1);
M.Step2_B6_UsablePct = NaN(height(M),1);
M.Step2_B7_UsablePct = NaN(height(M),1);
M.Step2_RT_DirectionChanges = NaN(height(M),1);
M.Step2_RT_ConsecutiveLargeJumps = NaN(height(M),1);
M.ExcludeStep2 = false(height(M),1);
M.Step2Reason = strings(height(M),1);

for i = 1:height(M)

    if M.ExcludeStep1(i)
        continue;
    end

    pid = M.ParticipantID(i);

    idx_original = Participant_step1 == pid;
    idx_filtered = Participant_filtered == pid;

    n_original = sum(idx_original);
    n_filtered = sum(idx_filtered);

    usableGlobalPct = (n_filtered / n_original) * 100;
    M.Step2_UsableGlobalPct(i) = usableGlobalPct;

    blockUsablePct = NaN(1,numel(stabilityBlocks));
    blockMedianRT = NaN(1,numel(stabilityBlocks));

    for b = 1:numel(stabilityBlocks)

        blk = stabilityBlocks(b);

        n_block_original = sum(idx_original & Block_step1 == blk);
        n_block_filtered = sum(idx_filtered & Block_filtered == blk);

        if n_block_original > 0
            blockUsablePct(b) = (n_block_filtered / n_block_original) * 100;
        end

        rt_b = RT_filtered(idx_filtered & Block_filtered == blk);
        if ~isempty(rt_b)
            blockMedianRT(b) = median(rt_b, "omitnan");
        end
    end

    idx_b6_original = idx_original & Block_step1 == 6;
    idx_b6_filtered = idx_filtered & Block_filtered == 6;
    
    idx_b7_original = idx_original & Block_step1 == 7;
    idx_b7_filtered = idx_filtered & Block_filtered == 7;
    
    M.Step2_B6_UsablePct(i) = (sum(idx_b6_filtered) / sum(idx_b6_original)) * 100;
    M.Step2_B7_UsablePct(i) = (sum(idx_b7_filtered) / sum(idx_b7_original)) * 100;

    validTrend = ~isnan(blockMedianRT);
    
    if sum(validTrend) >= 4
        y = blockMedianRT(validTrend);

        diffs = diff(y);
        
        minMeaningfulJump = 100; % ms
        
        meaningfulDiffs = diffs(abs(diffs) >= minMeaningfulJump);
        
        if numel(meaningfulDiffs) >= 2
            signs = sign(meaningfulDiffs);
            M.Step2_RT_DirectionChanges(i) = sum(diff(signs) ~= 0);
        else
            M.Step2_RT_DirectionChanges(i) = 0;
        end
        
        largeJumpMask = abs(diffs) >= minMeaningfulJump;
        largeJumpSigns = sign(diffs);
        
        consecutiveLargeSameDirection = 0;
        
        for jj = 1:(numel(diffs)-1)
            if largeJumpMask(jj) && largeJumpMask(jj+1) && largeJumpSigns(jj) == largeJumpSigns(jj+1)
                consecutiveLargeSameDirection = consecutiveLargeSameDirection + 1;
            end
        end
        
        M.Step2_RT_ConsecutiveLargeJumps(i) = consecutiveLargeSameDirection;

    end
end

for c = 1:numel(conditions)

    cond = conditions(c);
    idx_cond = M.SMART_length == cond & ~M.ExcludeStep1;

    direction_threshold = 2;

    rows = find(idx_cond);

    for r = 1:numel(rows)

        i = rows(r);
        reasons = strings(0,1);

        if M.Step2_UsableGlobalPct(i) <= 75
            reasons(end+1) = "Retains <=75% usable SMART trials globally";
        end

        if M.Step2_B6_UsablePct(i) <= 75
            reasons(end+1) = "Block 6 retains <=75% usable SMART trials after filtering";
        end
        
        if M.Step2_B7_UsablePct(i) <= 75
            reasons(end+1) = "Block 7 retains <=75% usable SMART trials after filtering";
        end

        if M.Step2_RT_DirectionChanges(i) >= direction_threshold
            reasons(end+1) = "Two or more meaningful RT direction changes across Blocks 1-6";
        end
        
        if M.Step2_RT_ConsecutiveLargeJumps(i) >= 1
            reasons(end+1) = "At least one pair of consecutive large RT jumps in the same direction across Blocks 1-6";
        end

        if ~isempty(reasons)
            M.ExcludeStep2(i) = true;
            M.Step2Reason(i) = strjoin(reasons, "; ");
        end
    end
end

% Step 5 — Save preprocessed datasets
step2Excluded = M.ParticipantID(M.ExcludeStep2);
allExcluded = unique([step1Excluded; step2Excluded]);

finalSmartKeep = ~ismember(Participant_filtered, allExcluded);
Ts_preprocessed = Ts_filtered(finalSmartKeep,:);

genKeep = ~ismember(Participant_g, allExcluded);
Tg_preprocessed = Tg(genKeep,:);

if hasDemo
    demoKeep = ~ismember(Participant_d, allExcluded);
    Td_preprocessed = Td(demoKeep,:);
end

writetable(Ts_preprocessed, smartOut);
writetable(Tg_preprocessed, genOut);

if hasDemo
    writetable(Td_preprocessed, demoOut);
end

% Step 5b — Extract demographic information from questionnaire files

demoSummaryOut = fullfile(resultsDir, "0_Demographics_Summary.txt");
demoTableOut   = fullfile(dataDir, "Demographics_Extracted_Preprocessed.xlsx");

demoAll = table();

for c = 1:numel(conditions)

    cond = conditions(c);

    qFile = fullfile(baseDir, cond, "combined_questionnaire_" + cond + ".xlsx");

    if ~isfile(qFile)
        warning("Questionnaire file not found: %s", qFile);
        continue;
    end

    Tq = readtable(qFile, "VariableNamingRule","preserve", "TextType","string");

    questionKey = string(Tq{:,37}); % Column AK
    response    = string(Tq{:,38}); % Column AL

    beginRows = find(questionKey == "BEGIN QUESTIONNAIRE");
    endRows   = find(questionKey == "END QUESTIONNAIRE");

    for i = 1:numel(endRows)

        eRow = endRows(i);

        bCandidates = beginRows(beginRows < eRow);
        if isempty(bCandidates)
            continue;
        end

        bRow = bCandidates(end);

        qBlock = questionKey(bRow:eRow);
        rBlock = response(bRow:eRow);

        pid = erase(strtrim(rBlock(qBlock == "END QUESTIONNAIRE")), "'");

        age       = rBlock(qBlock == "age-question");
        language  = rBlock(qBlock == "languages-question");
        ethnicity = rBlock(qBlock == "ethnicity-question");
        race      = rBlock(qBlock == "race-question");
        gender    = rBlock(qBlock == "gender-question");

        row = table();
        row.ParticipantID = pid;
        row.Condition = cond;
        row.Age = str2double(age);
        row.Language = strtrim(language);
        row.Ethnicity = strtrim(ethnicity);
        row.Race = strtrim(race);
        row.Gender = strtrim(gender);

        demoAll = [demoAll; row];

    end
end

% Keep only participants retained after preprocessing
demoAll = demoAll(~ismember(demoAll.ParticipantID, allExcluded), :);

writetable(demoAll, demoTableOut);

% Step 5c — Save demographic summary report

fidDemo = fopen(demoSummaryOut, 'w');
if fidDemo == -1
    error("Could not open demographic txt output file: %s", demoSummaryOut);
end

fprintf(fidDemo, "SMART DEMOGRAPHIC SUMMARY\n");
fprintf(fidDemo, "=========================\n\n");

fprintf(fidDemo, "Total retained participants with demographic data: %d\n", height(demoAll));
fprintf(fidDemo, "Mean age: %.2f\n", mean(demoAll.Age, "omitnan"));
fprintf(fidDemo, "Age SD: %.2f\n", std(demoAll.Age, "omitnan"));
fprintf(fidDemo, "Age range: %.0f - %.0f\n\n", min(demoAll.Age), max(demoAll.Age));

for c = 1:numel(conditions)

    cond = conditions(c);
    Dc = demoAll(demoAll.Condition == cond, :);

    fprintf(fidDemo, "Condition: %s\n", cond);
    fprintf(fidDemo, "==============================\n");
    fprintf(fidDemo, "N: %d\n", height(Dc));

    fprintf(fidDemo, "Age mean: %.2f\n", mean(Dc.Age, "omitnan"));
    fprintf(fidDemo, "Age SD: %.2f\n", std(Dc.Age, "omitnan"));
    fprintf(fidDemo, "Age range: %.0f - %.0f\n\n", min(Dc.Age), max(Dc.Age));

    fprintf(fidDemo, "Gender counts:\n");

    genderCats = unique(Dc.Gender);
    for j = 1:numel(genderCats)
        fprintf(fidDemo, "%s: %d\n", genderCats(j), sum(Dc.Gender == genderCats(j)));
    end

    fprintf(fidDemo, "\nRace counts:\n");
    raceCats = unique(Dc.Race);
    for j = 1:numel(raceCats)
        fprintf(fidDemo, "%s: %d\n", raceCats(j), sum(Dc.Race == raceCats(j)));
    end

    fprintf(fidDemo, "\nEthnicity counts:\n");
    ethCats = unique(Dc.Ethnicity);
    for j = 1:numel(ethCats)
        fprintf(fidDemo, "%s: %d\n", ethCats(j), sum(Dc.Ethnicity == ethCats(j)));
    end

    fprintf(fidDemo, "\nLanguage counts:\n");
    langCats = unique(Dc.Language);
    for j = 1:numel(langCats)
        fprintf(fidDemo, "%s: %d\n", langCats(j), sum(Dc.Language == langCats(j)));
    end

    fprintf(fidDemo, "\n\n");
end

fclose(fidDemo);

% Step 6 — Print preprocessing report
fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "SMART PREPROCESSING AND PARTICIPANT QC\n");
fprintf(fid, "======================================\n\n");

fprintf(fid, "GLOBAL RETENTION SUMMARY\n");
fprintf(fid, "========================\n");
fprintf(fid, "Initial SMART participants: %d\n", numel(unique(Participant)));
fprintf(fid, "Step 1 excluded participants: %d\n", numel(step1Excluded));
fprintf(fid, "Step 2 excluded participants: %d\n", numel(step2Excluded));
fprintf(fid, "Total excluded participants: %d\n", numel(allExcluded));
fprintf(fid, "Final retained participants: %d\n\n", numel(setdiff(unique(Participant), allExcluded)));

fprintf(fid, "Initial SMART trials: %d\n", height(Ts));
fprintf(fid, "SMART trials after participant exclusions and trial filter: %d\n\n", height(Ts_preprocessed));

for c = 1:numel(conditions)

    cond = conditions(c);
    idx = M.SMART_length == cond;
    Mc = M(idx,:);

    fprintf(fid, "Condition: %s\n", cond);
    fprintf(fid, "==============================\n");

    fprintf(fid, "Initial participants: %d\n", height(Mc));
    fprintf(fid, "Step 1 excluded: %d\n", sum(Mc.ExcludeStep1));
    fprintf(fid, "Step 2 excluded: %d\n", sum(Mc.ExcludeStep2));
    fprintf(fid, "Final retained: %d\n\n", sum(~Mc.ExcludeStep1 & ~Mc.ExcludeStep2));

    fprintf(fid, "Participant QC table:\n");
    fprintf(fid, "ID           Acc%%   RT<100%%   RT>1500%%   RT_Removed%%   Filtered_Global%%   Filtered_B6%%   Filtered_B7%%   DirChanges   ConsecJumps\n");

    for i = 1:height(Mc)
        fprintf(fid, "%s   %6.2f   %7.2f   %8.2f   %10.2f   %16.2f   %14.2f   %14.2f   %10.0f   %11.0f\n", ...
            string(Mc.ParticipantID(i)), ...
            Mc.GlobalAccuracy(i), ...
            Mc.PctFast(i), ...
            Mc.PctSlow(i), ...
            Mc.PctRemoved(i), ...
            Mc.Step2_UsableGlobalPct(i), ...
            Mc.Step2_B6_UsablePct(i), ...
            Mc.Step2_B7_UsablePct(i), ...
            Mc.Step2_RT_DirectionChanges(i), ...
            Mc.Step2_RT_ConsecutiveLargeJumps(i));
    end

    fprintf(fid, "\n");

    fprintf(fid, "STEP 1 EXCLUSIONS\n");
    rows = find(Mc.ExcludeStep1);
    if isempty(rows)
        fprintf(fid, "None\n\n");
    else
        fprintf(fid, "ID         Reason\n");
        for j = 1:numel(rows)
            r = rows(j);
            fprintf(fid, "%s   %s\n", string(Mc.ParticipantID(r)), string(Mc.Step1Reason(r)));
        end
        fprintf(fid, "\n");
    end

    fprintf(fid, "STEP 2 EXCLUSIONS\n");
    rows = find(Mc.ExcludeStep2);
    if isempty(rows)
        fprintf(fid, "None\n\n");
    else
        fprintf(fid, "ID         Reason\n");
        for j = 1:numel(rows)
            r = rows(j);
            fprintf(fid, "%s   %s\n", string(Mc.ParticipantID(r)), string(Mc.Step2Reason(r)));
        end
        fprintf(fid, "\n");
    end

    fprintf(fid, "\n");
end

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - First Part
% 1) Load SMART_Data_compressed_preprocessed.xlsx
% 2) Compute participant-level SMART metrics within each SMART_length group:
%    - Mean reaction time
%    - Mean reaction time per block
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - One-tailed paired t-test testing RT(Block 7) > RT(Block 6), FDR-corrected across conditions
% 3) Compare violation cost across SMART_length groups:
%    - One-way ANOVA across ms0, ms250, ms500, and ms1100
%    - Post-hoc pairwise comparisons only if test is significant
%    - FDR correction applied to post-hoc comparisons
% 4) Compute group summaries:
%    - Mean
%    - Median
%    - 95% confidence interval for block-wise RT means
% 5) Save results to a txt file
% 6) Create one reaction-time plot per SMART_length group
% 7) Create participant-level RT plots per SMART_length group
% 8) Create one RT6 vs RT7 plot across SMART_length groups
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "1_SMART_RT_results.txt");
plotOutRT6RT7 = fullfile(resultsDir, "1_SMART_RT6_vs_RT7.png");

T = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(T.("Reaction Time")), "'"));
Block = str2double(erase(string(T.("block")), "'"));
Participant_full = erase(string(T.("Participant Private ID")), "'");
SMART_length = string(T.("SMART_length"));

conditions = ["ms0", "ms250", "ms500", "ms1100"];
blocks = 1:8;

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [0.85 0.33 0.10];
condColors('ms250')  = [0.10 0.35 0.85];
condColors('ms500')  = [0.10 0.65 0.20];
condColors('ms1100') = [0.85 0.10 0.10];

% Global Y-axis limits across all participants and blocks
RT_block_all = NaN(numel(unique(Participant_full)), numel(blocks));
allParticipants = unique(Participant_full);

for p = 1:numel(allParticipants)
    pid = allParticipants(p);
    idx = Participant_full == pid;

    RT_p = RT(idx);
    Block_p = Block(idx);

    for b = 1:numel(blocks)
        blockIdx = Block_p == blocks(b);
        if any(blockIdx)
            RT_block_all(p,b) = mean(RT_p(blockIdx), "omitnan");
        end
    end
end

yMin = floor(min(RT_block_all(:), [], "omitnan"));
yMax = ceil(max(RT_block_all(:), [], "omitnan"));
yPad = 0.05 * (yMax - yMin);
yMin = yMin - yPad;
yMax = yMax + yPad;

% Store condition-level outputs before printing
results = struct();
p_block67 = NaN(numel(conditions),1);

for c = 1:numel(conditions)

    condName = conditions(c);
    condIdx = SMART_length == condName;

    if ~any(condIdx)
        results(c).hasData = false;
        results(c).condName = condName;
        continue;
    end

    RT_c = RT(condIdx);
    Block_c = Block(condIdx);
    Participant_full_c = Participant_full(condIdx);

    participants = unique(Participant_full_c);
    nP = length(participants);
    participants_id = participants;

    RT_block_p = NaN(nP, length(blocks));
    meanRT_p = zeros(nP,1);
    violationCost_p = NaN(nP,1);

    for p = 1:nP
    
        pid = participants(p);
        idx = Participant_full_c == pid;

        RT_p = RT_c(idx);
        Block_p = Block_c(idx);

        % RT per block from RT-filtered data
        for b = 1:length(blocks)
            blockIdx = Block_p == blocks(b);
            if any(blockIdx)
                RT_block_p(p,b) = mean(RT_p(blockIdx), "omitnan");
            end
        end

        % Mean RT from RT-filtered data
        meanRT_p(p) = mean(RT_p, "omitnan");

        % Violation cost from RT-filtered data
        if any(Block_p == 6) && any(Block_p == 7)
            RT6_i = mean(RT_p(Block_p == 6), "omitnan");
            RT7_i = mean(RT_p(Block_p == 7), "omitnan");
            violationCost_p(p) = RT7_i - RT6_i;
        end
    end

    % Group summaries
    meanRT_global = mean(meanRT_p, "omitnan");
    RT_block_global = mean(RT_block_p, 1, "omitnan");
    violationCost_global = mean(violationCost_p, "omitnan");

    meanRT_global_med = median(meanRT_p, "omitnan");
    RT_block_global_med = median(RT_block_p, 1, "omitnan");
    violationCost_global_med = median(violationCost_p, "omitnan");

    % 95% CI for block-wise RT means
    RT_block_n = sum(~isnan(RT_block_p), 1);
    RT_block_sem = std(RT_block_p, 0, 1, "omitnan") ./ sqrt(RT_block_n);
    RT_block_ci95 = NaN(size(RT_block_global));
    RT_block_ci95_low = NaN(size(RT_block_global));
    RT_block_ci95_high = NaN(size(RT_block_global));

    for b = 1:length(blocks)
        if RT_block_n(b) > 1
            RT_block_ci95(b) = tinv(0.975, RT_block_n(b)-1) * RT_block_sem(b);
            RT_block_ci95_low(b) = RT_block_global(b) - RT_block_ci95(b);
            RT_block_ci95_high(b) = RT_block_global(b) + RT_block_ci95(b);
        end
    end

    % Block 6 vs 7 paired t-test
    RT6 = RT_block_p(:,6);
    RT7 = RT_block_p(:,7);

    valid = ~isnan(RT6) & ~isnan(RT7);
    RT6 = RT6(valid);
    RT7 = RT7(valid);

    [~, p_ttest, ~, stats_ttest] = ttest(RT7, RT6, 'Tail','right');
    p_block67(c) = p_ttest;

    % Store everything
    results(c).hasData = true;
    results(c).condName = condName;
    results(c).participants_id = participants;
    results(c).nP = nP;

    results(c).RT_block_p = RT_block_p;

    results(c).meanRT_p = meanRT_p;
    results(c).violationCost_p = violationCost_p;

    results(c).meanRT_global = meanRT_global;
    results(c).RT_block_global = RT_block_global;
    results(c).violationCost_global = violationCost_global;

    results(c).meanRT_global_med = meanRT_global_med;
    results(c).RT_block_global_med = RT_block_global_med;
    results(c).violationCost_global_med = violationCost_global_med;

    results(c).RT_block_n = RT_block_n;
    results(c).RT_block_sem = RT_block_sem;
    results(c).RT_block_ci95 = RT_block_ci95;
    results(c).RT_block_ci95_low = RT_block_ci95_low;
    results(c).RT_block_ci95_high = RT_block_ci95_high;

    results(c).RT6 = RT6;
    results(c).RT7 = RT7;
    results(c).tstat = stats_ttest.tstat;
    results(c).p_ttest = p_ttest;
end

% FDR correction across Block 6 vs 7 paired t-tests
validP = ~isnan(p_block67);
pvals = p_block67(validP);

p_block67_fdr = NaN(size(p_block67));

if ~isempty(pvals)

    [p_sorted, sortIdx] = sort(pvals(:));
    m = numel(p_sorted);

    p_fdr_sorted = p_sorted .* m ./ (1:m)';

    for i = m-1:-1:1
        p_fdr_sorted(i) = min(p_fdr_sorted(i), p_fdr_sorted(i+1));
    end

    p_fdr_sorted = min(p_fdr_sorted, 1);

    p_fdr_valid = NaN(size(pvals(:)));
    p_fdr_valid(sortIdx) = p_fdr_sorted;

    p_block67_fdr(validP) = p_fdr_valid;
end

% Compare violation cost across conditions
allViol = [];
allGroups = [];

for c = 1:numel(conditions)
    if results(c).hasData
        vc = results(c).violationCost_p;
        grp = repmat(string(results(c).condName), numel(vc), 1);

        valid = ~isnan(vc);
        allViol = [allViol; vc(valid)];
        allGroups = [allGroups; grp(valid)];
    end
end

% ANOVA path
[p_anova, tbl_anova, stats_anova] = anova1(allViol, allGroups, 'off');

SS_between = tbl_anova{2,2};
SS_within  = tbl_anova{3,2};
SS_total   = tbl_anova{4,2};

df_between = tbl_anova{2,3};
df_within  = tbl_anova{3,3};

MS_within = tbl_anova{3,4};

F_anova = tbl_anova{2,5};

eta2_anova = SS_between / SS_total;
partial_eta2_anova = SS_between / (SS_between + SS_within);

omega2_anova = (SS_between - df_between * MS_within) / ...
               (SS_total + MS_within);

doPosthoc_anova = false;
c_mult_anova = [];
p_fdr_posthoc_anova = [];

if p_anova < 0.05

    doPosthoc_anova = true;

    c_mult_anova = multcompare(stats_anova, 'Display','off');
    pairwise_p_anova = c_mult_anova(:,6);

    validP = ~isnan(pairwise_p_anova);
    pvals = pairwise_p_anova(validP);

    p_fdr_posthoc_anova = NaN(size(pairwise_p_anova));

    if ~isempty(pvals)

        [p_sorted, sortIdx] = sort(pvals(:));
        m = numel(p_sorted);

        p_fdr_sorted = p_sorted .* m ./ (1:m)';

        for i = m-1:-1:1
            p_fdr_sorted(i) = min(p_fdr_sorted(i), p_fdr_sorted(i+1));
        end

        p_fdr_sorted = min(p_fdr_sorted, 1);

        p_fdr_valid = NaN(size(pvals(:)));
        p_fdr_valid(sortIdx) = p_fdr_sorted;

        p_fdr_posthoc_anova(validP) = p_fdr_valid;
    end
end

% Write output
fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "SMART TASK RESULTS\n");
fprintf(fid, "==================\n\n");
fprintf(fid, "Input file: %s\n\n", smartFile);

for c = 1:numel(conditions)

    condName = conditions(c);

    if ~results(c).hasData
        fprintf(fid, "Condition: %s\n", condName);
        fprintf(fid, "No data found.\n\n");
        continue;
    end

    participants_id = results(c).participants_id;
    nP = results(c).nP;

    RT_block_p = results(c).RT_block_p;

    meanRT_p = results(c).meanRT_p;
    violationCost_p = results(c).violationCost_p;

    fprintf(fid, "Condition: %s\n", condName);
    fprintf(fid, "=============================\n");

    fprintf(fid, "RT per block per participant (ms):\n");
    for p = 1:nP
        fprintf(fid, "%s: ", results(c).participants_id(min(p,end)));
        fprintf(fid, "%.2f ", RT_block_p(p,:));
        fprintf(fid, "\n");
    end
    fprintf(fid, "\n");

    fprintf(fid, "RT per block (mean):   ");
    fprintf(fid, "%6.2f ", results(c).RT_block_global);
    fprintf(fid, "\n");

    fprintf(fid, "RT per block (median): ");
    fprintf(fid, "%6.2f ", results(c).RT_block_global_med);
    fprintf(fid, "\n");

    fprintf(fid, "RT per block n:        ");
    fprintf(fid, "%6d ", results(c).RT_block_n);
    fprintf(fid, "\n");

    fprintf(fid, "RT per block 95%% CI lower: ");
    fprintf(fid, "%6.2f ", results(c).RT_block_ci95_low);
    fprintf(fid, "\n");

    fprintf(fid, "RT per block 95%% CI upper: ");
    fprintf(fid, "%6.2f ", results(c).RT_block_ci95_high);
    fprintf(fid, "\n");

    fprintf(fid, "RT per block 95%% CI half-width: ");
    fprintf(fid, "%6.2f ", results(c).RT_block_ci95);
    fprintf(fid, "\n\n");

    fprintf(fid, "PARTICIPANT SUMMARY\n");
    fprintf(fid, "ID    MeanRT(ms)   Viol_7-6(ms)\n");
    for p = 1:nP
        fprintf(fid, "%s   %7.2f   %10.2f\n", ...
            results(c).participants_id(min(p,end)), ...
            meanRT_p(p), ...
            violationCost_p(p));
    end
    fprintf(fid, "\n");

    fprintf(fid, "GROUP SUMMARY\n");

    fprintf(fid, "Mean RT (ms)        | mean: %6.2f | median: %6.2f\n", ...
        results(c).meanRT_global, results(c).meanRT_global_med);

    fprintf(fid, "Violation cost (ms) | mean: %6.2f | median: %6.2f\n\n", ...
        results(c).violationCost_global, results(c).violationCost_global_med);

    fprintf(fid, "BLOCK 6 vs 7 (RT)\n");
    fprintf(fid, "Mean RT6 = %.2f | Mean RT7 = %.2f\n", ...
        mean(results(c).RT6), mean(results(c).RT7));

    fprintf(fid, "One-tailed paired t-test: t = %.2f | p = %.4f | p_FDR = %.4f\n\n", ...
        results(c).tstat, results(c).p_ttest, p_block67_fdr(c));

    fprintf(fid, "\n");

    % Plot RT per block for this condition
    figure('Position',[300 300 500 350]);
    hold on

    for p = 1:size(RT_block_p,1)
        plot(blocks, RT_block_p(p,:), ...
            '-o', ...
            'Color', [0.7 0.7 0.7], ...
            'MarkerFaceColor', [0.7 0.7 0.7], ...
            'LineWidth', 1, ...
            'MarkerSize', 5);
    end

    thisColor = condColors(char(condName));

    errorbar(blocks, results(c).RT_block_global, results(c).RT_block_ci95, ...
        'Color', thisColor, ...
        'LineStyle', 'none', ...
        'LineWidth', 1.5, ...
        'CapSize', 8);

    plot(blocks, results(c).RT_block_global, ...
        '-o', ...
        'Color', thisColor, ...
        'MarkerFaceColor', thisColor, ...
        'LineWidth', 2, ...
        'MarkerSize', 7);

    xlabel('Block');
    ylabel('Reaction Time (ms)');
    ylim([yMin yMax]);

    cleanCond = erase(condName, "ms");
    title("SMART " + cleanCond + " ms", 'Interpreter', 'none');

    xlim([0.5 8.5]);
    xticks(1:8);

    box off
    set(gca,'FontSize',10)
    hold off

    saveas(gcf, fullfile(resultsDir, "1_SMART_RT_" + condName + ".png"));
    close

    condPlotFolder = fullfile(resultsDir, condName);

    if ~exist(condPlotFolder, 'dir')
        mkdir(condPlotFolder);
    end
    
    for p = 1:nP
    
        figure('Position',[300 300 500 350]);
        hold on
    
        % --- ALL participants (gray) ---
        for pp = 1:nP
            plot(blocks, RT_block_p(pp,:), ...
                '-o', ...
                'Color', [0.7 0.7 0.7], ...
                'MarkerFaceColor', [0.7 0.7 0.7], ...
                'LineWidth', 1, ...
                'MarkerSize', 5);
        end
    
        thisColor = condColors(char(condName));
    
        % --- GROUP MEAN 95% CI ---
        errorbar(blocks, results(c).RT_block_global, results(c).RT_block_ci95, ...
            'Color', thisColor, ...
            'LineStyle', 'none', ...
            'LineWidth', 1.5, ...
            'CapSize', 8);

        % --- GROUP MEAN ---
        plot(blocks, results(c).RT_block_global, ...
            '-o', ...
            'Color', thisColor, ...
            'MarkerFaceColor', thisColor, ...
            'LineWidth', 2, ...
            'MarkerSize', 7);
    
        % --- ONE PARTICIPANT (highlighted) ---
        plot(blocks, RT_block_p(p,:), ...
            '-o', ...
            'Color', thisColor, ...
            'MarkerFaceColor', thisColor, ...
            'MarkerEdgeColor', 'k', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 7);
    
        xlabel('Block');
        ylabel('Reaction Time (ms)');
        ylim([yMin yMax]);
        xlim([0.5 8.5]);
        xticks(1:8);
    
        pid = participants_id(p);
        cleanCond = erase(condName, "ms");
    
        title("SMART " + cleanCond + " ms | ID: " + pid, 'Interpreter','none');
    
        box off
        set(gca,'FontSize',10)
    
        hold off
    
        saveas(gcf, fullfile(condPlotFolder, ...
            "RT_" + condName + "_ID_" + pid + ".png"));
    
        close
    
    end
end

fprintf(fid, "VIOLATION COST ACROSS CONDITIONS\n");
fprintf(fid, "================================\n");
fprintf(fid, "ANOVA: F(%d,%d) = %.4f | p = %.4f | eta2 = %.4f | partial_eta2 = %.4f | omega2 = %.4f\n", ...
    df_between, df_within, F_anova, p_anova, ...
    eta2_anova, partial_eta2_anova, omega2_anova);

if doPosthoc_anova

    fprintf(fid, "ANOVA post-hoc comparisons (FDR corrected):\n");

    for i = 1:size(c_mult_anova,1)
        fprintf(fid, "%s vs %s | p = %.4f | p_FDR = %.4f\n", ...
            conditions(c_mult_anova(i,1)), ...
            conditions(c_mult_anova(i,2)), ...
            c_mult_anova(i,6), ...
            p_fdr_posthoc_anova(i));
    end
end

% Plot RT6 vs RT7 by condition
figure('Position',[200 300 1200 350]);

for c = 1:numel(conditions)

    cond = conditions(c);

    if ~results(c).hasData
        continue;
    end

    RT6 = results(c).RT6;
    RT7 = results(c).RT7;
    participants_id = results(c).participants_id;
    
    subplot(1,4,c)
    hold on

    thisColor = condColors(char(cond));

    scatter(RT6, RT7, 45, thisColor, 'filled');

    for i = 1:length(RT6)
        text(RT6(i) + 2, RT7(i), participants_id(i), 'FontSize', 6);
    end

    minVal = floor(min([RT6; RT7], [], "omitnan"));
    maxVal = ceil(max([RT6; RT7], [], "omitnan"));

    plot([minVal maxVal], [minVal maxVal], 'k--', 'LineWidth', 1);

    xlabel('RT Block 6 (ms)', 'FontSize', 8);
    ylabel('RT Block 7 (ms)', 'FontSize', 8);

    cleanCond = erase(cond, "ms");
    title(cleanCond + " ms: t = " + sprintf('%.2f', results(c).tstat) + ...
          ", p_FDR = " + sprintf('%.4f', p_block67_fdr(c)), ...
          'Interpreter','none','FontSize',9);

    xlim([minVal maxVal]);
    ylim([minVal maxVal]);

    box off
    set(gca,'FontSize',7);
    hold off
end

saveas(gcf, plotOutRT6RT7);
close

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Second Part
% 1) Load Generalization_Data_compressed_preprocessed.xlsx
% 2) Analyze performance separately within each SMART_length group
%    (ms0, ms250, ms500, ms1100)
% 3) Compute participant-level generalization accuracy:
%    - UNI trials (descriptive only)
%    - MULTI trials (descriptive only)
%    - Global generalization (GenMean = mean of UNI and MULTI)
% 4) Test GenMean vs chance (25%) within each SMART_length group:
%    - One-sample t-test (right-tailed)
%    - FDR correction across conditions
% 5) Compare GenMean across SMART_length groups:
%    - One-way ANOVA across ms0, ms250, ms500, and ms1100
%    - F statistic, df, p value, eta-squared, omega-squared
%    - Post-hoc pairwise comparisons only if test is significant
%    - FDR correction applied to post-hoc comparisons
% 6) Planned contrast:
%    - Welch's t-test: ms0 vs pooled longer ISIs (ms250 + ms500 + ms1100)
%    - Cohen's d and Hedges' g
% 7) Save results to a txt file
% 8) Create plots:
%    - UNI vs MULTI (descriptive only)
%    - Global generalization across all conditions
%    - Global generalization violin plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "2_Generalization_results.txt");

T = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

findVar = @(hdr) localFindVarName(hdr, T);

idVar      = findVar("Participant Private ID");
correctVar = findVar("Correct");
catVar     = findVar("Category");
smartVar   = findVar("SMART_length");

Correct = str2double(erase(string(T.(correctVar)), "'"));
Participant_full = erase(string(T.(idVar)), "'");
Category = erase(string(T.(catVar)), "'");
SMART_length = string(T.(smartVar));

conditions = ["ms0", "ms250", "ms500", "ms1100"];

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [1.00 0.75 0.60; 0.85 0.33 0.10];
condColors('ms250')  = [0.75 0.85 1.00; 0.10 0.35 0.85];
condColors('ms500')  = [0.75 1.00 0.75; 0.10 0.65 0.20];
condColors('ms1100') = [1.00 0.75 0.75; 0.85 0.10 0.10];

results = struct();
p_gen = NaN(numel(conditions),1);

for c = 1:numel(conditions)

    condName = conditions(c);
    condIdx = SMART_length == condName;

    if ~any(condIdx)
        results(c).hasData = false;
        results(c).condName = condName;
        continue;
    end

    Participant_full_c = Participant_full(condIdx);
    Correct_c = Correct(condIdx);
    Category_c = Category(condIdx);

    participants = unique(Participant_full_c);
    nP = length(participants);

    participants_id = participants;

    gen_uni_p = NaN(nP,1);
    gen_multi_p = NaN(nP,1);
    gen_mean_p = NaN(nP,1);

    for p = 1:nP

        pid = participants(p);
        idx = Participant_full_c == pid;

        Correct_p = Correct_c(idx);
        Category_p = Category_c(idx);

        uni_idx = Category_p == "uni";
        multi_idx = Category_p == "multi";

        if any(uni_idx)
            gen_uni_p(p) = mean(Correct_p(uni_idx) == 1);
        end

        if any(multi_idx)
            gen_multi_p(p) = mean(Correct_p(multi_idx) == 1);
        end

        gen_mean_p(p) = mean([gen_uni_p(p), gen_multi_p(p)], "omitnan") * 100;
        gen_uni_p(p)   = gen_uni_p(p) * 100;
        gen_multi_p(p) = gen_multi_p(p) * 100;
    end

    valid = ~isnan(gen_mean_p);
    xvals = gen_mean_p(valid);

    [~, p_val, ~, stats] = ttest(xvals, 25, 'Tail','right');
    p_gen(c) = p_val;

    results(c).hasData = true;
    results(c).condName = condName;
    results(c).participants_id = participants;
    results(c).nP = nP;

    results(c).gen_uni_p = gen_uni_p;
    results(c).gen_multi_p = gen_multi_p;
    results(c).gen_mean_p = gen_mean_p;

    results(c).gen_mean_mean = mean(gen_mean_p, "omitnan");
    results(c).gen_mean_median = median(gen_mean_p, "omitnan");
    results(c).gen_mean_sd = std(gen_mean_p, "omitnan");

    results(c).tstat = stats.tstat;
    results(c).p_val = p_val;

    results(c).n = sum(~isnan(gen_mean_p));
    results(c).sem = results(c).gen_mean_sd / sqrt(results(c).n);
    results(c).ci95 = tinv(0.975, results(c).n - 1) * results(c).sem;
    results(c).ci95_low  = results(c).gen_mean_mean - results(c).ci95;
    results(c).ci95_high = results(c).gen_mean_mean + results(c).ci95;
end

% FDR correction across GenMean vs chance tests
validP = ~isnan(p_gen);
pvals = p_gen(validP);

p_gen_fdr = NaN(size(p_gen));

if ~isempty(pvals)

    [p_sorted, sortIdx] = sort(pvals(:));
    m = numel(p_sorted);

    p_fdr_sorted = p_sorted .* m ./ (1:m)';

    for i = m-1:-1:1
        p_fdr_sorted(i) = min(p_fdr_sorted(i), p_fdr_sorted(i+1));
    end

    p_fdr_sorted = min(p_fdr_sorted, 1);

    p_fdr_valid = NaN(size(pvals(:)));
    p_fdr_valid(sortIdx) = p_fdr_sorted;

    p_gen_fdr(validP) = p_fdr_valid;
end

% Global comparison across conditions
all_gen = [];
all_groups = [];

for c = 1:numel(conditions)
    if results(c).hasData
        xvals = results(c).gen_mean_p;
        xvals = xvals(~isnan(xvals));

        all_gen = [all_gen; xvals];
        all_groups = [all_groups; repmat(string(conditions(c)), numel(xvals), 1)];
    end
end

% ANOVA: GenMean across conditions
[p_anova, tbl_anova, stats_anova] = anova1(all_gen, all_groups, 'off');

SS_between = tbl_anova{2,2};
SS_within  = tbl_anova{3,2};
SS_total   = tbl_anova{4,2};

df_between = tbl_anova{2,3};
df_within  = tbl_anova{3,3};

MS_within = tbl_anova{3,4};

F_anova = tbl_anova{2,5};

eta2_anova = SS_between / SS_total;
partial_eta2_anova = SS_between / (SS_between + SS_within);

omega2_anova = (SS_between - df_between * MS_within) / ...
               (SS_total + MS_within);

pairwise_results_anova = [];

if p_anova < 0.05

    c_mult_anova = multcompare(stats_anova, 'Display','off');
    p_pair_anova = c_mult_anova(:,6);

    [p_sorted, sortIdx] = sort(p_pair_anova);
    m = numel(p_sorted);

    p_fdr_sorted = p_sorted .* m ./ (1:m)';

    for i = m-1:-1:1
        p_fdr_sorted(i) = min(p_fdr_sorted(i), p_fdr_sorted(i+1));
    end

    p_fdr_sorted = min(p_fdr_sorted, 1);

    p_fdr_anova = NaN(size(p_pair_anova));
    p_fdr_anova(sortIdx) = p_fdr_sorted;

    pairwise_results_anova = [c_mult_anova(:,1:2), p_pair_anova, p_fdr_anova];
end

% Planned contrast:
% ms0 vs pooled longer ISIs with Welch's t-test
ms0_vals = results(1).gen_mean_p;
ms0_vals = ms0_vals(~isnan(ms0_vals));

long_vals = [];

for c = 2:numel(conditions)
    xvals = results(c).gen_mean_p;
    xvals = xvals(~isnan(xvals));
    long_vals = [long_vals; xvals];
end

[~, p_ms0_vs_long, ~, stats_ms0_vs_long] = ...
    ttest2(ms0_vals, long_vals, 'Vartype','unequal');

mean_ms0 = mean(ms0_vals, "omitnan");
mean_long = mean(long_vals, "omitnan");

sd_ms0 = std(ms0_vals, "omitnan");
sd_long = std(long_vals, "omitnan");

n_ms0 = numel(ms0_vals);
n_long = numel(long_vals);

spooled = sqrt(((n_ms0 - 1)*sd_ms0^2 + (n_long - 1)*sd_long^2) / ...
               (n_ms0 + n_long - 2));

cohens_d_ms0_vs_long = (mean_ms0 - mean_long) / spooled;

J = 1 - (3 / (4*(n_ms0 + n_long) - 9));
hedges_g_ms0_vs_long = cohens_d_ms0_vs_long * J;

df_welch = stats_ms0_vs_long.df;

% Write output
fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "GENERALIZATION RESULTS\n");
fprintf(fid, "======================\n\n");
fprintf(fid, "Input file: %s\n\n", genFile);

for c = 1:numel(conditions)

    condName = conditions(c);

    participants_id = results(c).participants_id;
    nP = results(c).nP;

    gen_uni_p = results(c).gen_uni_p;
    gen_multi_p = results(c).gen_multi_p;
    gen_mean_p = results(c).gen_mean_p;

    fprintf(fid, "Condition: %s\n", condName);
    fprintf(fid, "=============================\n");

    fprintf(fid, "PARTICIPANT GENERALIZATION\n");
    fprintf(fid, "ID    UNI(%%)   MULTI(%%)   GenMean(%%)\n");
    
    for p = 1:nP
        fprintf(fid, "%s   %7.2f   %9.2f   %10.2f\n", ...
            participants_id(p), gen_uni_p(p), gen_multi_p(p), gen_mean_p(p));
    end
    
    fprintf(fid, "\n");

    fprintf(fid, "GLOBAL SUMMARY\n");
    fprintf(fid, "GenMean | mean = %.2f | median = %.2f | SD = %.2f\n", ...
        results(c).gen_mean_mean, results(c).gen_mean_median, results(c).gen_mean_sd);

    fprintf(fid, "n = %d\n", results(c).n);
    fprintf(fid, "95%% CI = [%.2f, %.2f]\n", ...
        results(c).ci95_low, results(c).ci95_high);

    fprintf(fid, "One-sample t-test vs 25%%: t = %.2f | p = %.4f | p_FDR = %.4f\n\n", ...
        results(c).tstat, results(c).p_val, p_gen_fdr(c));

    % ----------------- PLOT 1: UNI vs MULTI (DESCRIPTIVE) -----------------
    figure('Position',[400 300 380 400]);
    hold on

    thisColors = condColors(char(condName));
    lightColor = thisColors(1,:);
    darkColor  = thisColors(2,:);

    bar(1, mean(gen_uni_p,"omitnan"), 0.6, ...
        'FaceColor', lightColor, ...
        'EdgeColor', 'none');

    bar(2, mean(gen_multi_p,"omitnan"), 0.6, ...
        'FaceColor', darkColor, ...
        'EdgeColor', 'none');

    errorbar([1 2], ...
        [mean(gen_uni_p,"omitnan") mean(gen_multi_p,"omitnan")], ...
        [std(gen_uni_p,"omitnan") std(gen_multi_p,"omitnan")], ...
        'k', ...
        'LineStyle', 'none', ...
        'LineWidth', 1.5, ...
        'CapSize', 10);

    scatter(ones(size(gen_uni_p)), gen_uni_p, ...
        35, [0.5 0.5 0.5], 'filled', ...
        'jitter', 'on', 'jitterAmount', 0.08);

    scatter(2*ones(size(gen_multi_p)), gen_multi_p, ...
        35, [0.5 0.5 0.5], 'filled', ...
        'jitter', 'on', 'jitterAmount', 0.08);

    yline(25, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.2);

    xlim([0.5 2.5]);
    xticks([1 2]);
    xticklabels({'Unidimensional','Multidimensional'});

    ylabel('Generalization Performance (%)');

    cleanCond = erase(condName, "ms");
    title("Generalization " + cleanCond + " ms:" + newline + ...
          "t = " + sprintf('%.2f', results(c).tstat) + ...
          ", p_FDR = " + sprintf('%.4f', p_gen_fdr(c)), ...
          'Interpreter','none');
    
    grid on
    ax = gca;
    ax.XGrid = 'off';
    ax.YGrid = 'on';

    box off
    set(gca, 'FontSize', 10)

    hold off
    saveas(gcf, fullfile(resultsDir, "2_Generalization_UNI_MULTI_" + condName + ".png"));
    close
end

fprintf(fid, "GLOBAL COMPARISON ACROSS CONDITIONS\n");
fprintf(fid, "===================================\n");
fprintf(fid, "ANOVA: F(%d,%d) = %.4f | p = %.4f | eta2 = %.4f | partial_eta2 = %.4f | omega2 = %.4f\n", ...
    df_between, df_within, F_anova, p_anova, eta2_anova, partial_eta2_anova, omega2_anova);

if p_anova < 0.05
    fprintf(fid, "ANOVA post-hoc pairwise comparisons (FDR-corrected):\n");
    for i = 1:size(pairwise_results_anova,1)
        c1 = pairwise_results_anova(i,1);
        c2 = pairwise_results_anova(i,2);
        p_raw = pairwise_results_anova(i,3);
        p_corr = pairwise_results_anova(i,4);

        fprintf(fid, "%s vs %s | p = %.4f | p_FDR = %.4f\n", ...
            conditions(c1), conditions(c2), p_raw, p_corr);
    end
end

fprintf(fid, "\n");
fprintf(fid, "PLANNED CONTRAST: ms0 vs pooled longer ISIs\n");
fprintf(fid, "-------------------------------------------\n");

fprintf(fid, "ms0 | n = %d | mean = %.2f | SD = %.2f\n", ...
    n_ms0, mean_ms0, sd_ms0);

fprintf(fid, "Longer ISIs pooled | n = %d | mean = %.2f | SD = %.2f\n", ...
    n_long, mean_long, sd_long);

fprintf(fid, "Welch t(%.2f) = %.4f | p = %.4f | Cohen's d = %.4f | Hedges' g = %.4f\n", ...
    df_welch, stats_ms0_vs_long.tstat, p_ms0_vs_long, ...
    cohens_d_ms0_vs_long, hedges_g_ms0_vs_long);

fprintf(fid, "\n");

% ----------------- PLOT 2: GLOBAL GENERALIZATION (ALL CONDITIONS) -----------------
figure('Position',[400 300 500 400]);
hold on

nC = numel(conditions);
means = NaN(nC,1);
sds   = NaN(nC,1);

for c = 1:nC
    if results(c).hasData
        means(c) = results(c).gen_mean_mean;
        sds(c)   = results(c).gen_mean_sd;
    end
end

x = 1:nC;

for c = 1:nC
    thisColors = condColors(char(conditions(c)));
    darkColor = thisColors(2,:);

    bar(x(c), means(c), 0.6, ...
        'FaceColor', darkColor, ...
        'EdgeColor', 'none');
end

errorbar(x, means, sds, ...
    'k', ...
    'LineStyle','none', ...
    'LineWidth',1.5, ...
    'CapSize',10);

for c = 1:nC
    if results(c).hasData
        yvals = results(c).gen_mean_p;
        scatter(c*ones(size(yvals)), yvals, ...
            35, [0.5 0.5 0.5], 'filled', ...
            'jitter','on', 'jitterAmount',0.08);
    end
end

yline(25, '--', 'Color',[0.3 0.3 0.3], 'LineWidth',1.2);

xlim([0.5 nC+0.5]);
xticks(x);
xticklabels({'0 ms','250 ms','500 ms','1100 ms'});

ylabel('Generalization Performance (%)');
title("Global Generalization:" + newline + ...
      "F(" + string(df_between) + "," + string(df_within) + ") = " + ...
      sprintf('%.2f', F_anova) + ...
      ", p = " + sprintf('%.4f', p_anova), ...
      'Interpreter','none');

grid on
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'on';

box off
set(gca,'FontSize',10);

hold off
saveas(gcf, fullfile(resultsDir, "2_Generalization_Global_All.png"));
close

% ----------------- PLOT 3: GLOBAL GENERALIZATION VIOLIN PLOT -----------------
figure('Position',[400 300 620 420]);
hold on

nC = numel(conditions);
x = 1:nC;

densityBandwidth = 0.35;
violinWidth = 0.22;

for c = 1:nC

    if ~results(c).hasData
        continue;
    end

    yvals = results(c).gen_mean_p;
    yvals = yvals(~isnan(yvals));

    thisColors = condColors(char(conditions(c)));
    darkColor = thisColors(2,:);

    if numel(yvals) >= 4
        [f, xi] = ksdensity(yvals, ...
            'Support',[0 100], ...
            'Bandwidth',densityBandwidth);

        f = f / max(f);
        f = f * violinWidth;

        fill([x(c)-f, fliplr(x(c)+f)], ...
             [xi, fliplr(xi)], ...
             darkColor, ...
             'EdgeColor', darkColor, ...
             'FaceAlpha', 0.35);
    end

    xj = x(c) + (rand(size(yvals)) - 0.5) * 0.16;

    scatter(xj, yvals, 35, ...
        'MarkerFaceColor', [0.7 0.7 0.7], ...
        'MarkerFaceAlpha', 0.45, ...
        'MarkerEdgeColor', [0.35 0.35 0.35], ...
        'MarkerEdgeAlpha', 0.70);

    m = mean(yvals, "omitnan");
    sem = std(yvals, "omitnan") / sqrt(numel(yvals));
    ci95 = tinv(0.975, numel(yvals)-1) * sem;

    errorbar(x(c), m, ci95, ...
        'k', ...
        'LineStyle','none', ...
        'LineWidth',1.8, ...
        'CapSize',12);

    scatter(x(c), m, ...
        120, ...
        'MarkerFaceColor', darkColor, ...
        'MarkerEdgeColor', 'k', ...
        'LineWidth', 1.5);

end

yline(25, '--', 'Color',[0.3 0.3 0.3], 'LineWidth',1.2);

xlim([0.5 nC+0.5]);
ylim([0 100]);

xticks(x);
xticklabels({'0 ms','250 ms','500 ms','1100 ms'});

ylabel('Generalization Performance (%)');
title("Global Generalization - Violin Plot", ...
      'Interpreter','none');

grid on
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'on';

box off
set(gca,'FontSize',10);

hold off

saveas(gcf, fullfile(resultsDir, "2_Generalization_Global_Violin.png"));
close

fclose(fid);

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Third Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level SMART metrics:
%    - RT Block 6
%    - RT Block 7
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - RT learning slope across Blocks 1–6
% 3) Build participant-level Generalization metric:
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 4) Join SMART and Generalization summaries by participant and SMART_length
% 5) Within each SMART_length group, test Pearson correlations:
%    - Violation cost vs GenMean
%    - RT Block 6 vs GenMean
%    - RT slope Blocks 1–6 vs GenMean
%    - FDR correction across the three correlations within each group
% 6) Compare RT Block 6 and RT slope across SMART_length groups:
%    - One-way ANOVA across ms0, ms250, ms500, and ms1100
%    - Post-hoc pairwise comparisons only if test is significant
%    - FDR correction applied separately to RT6 and slope post-hoc comparisons
% 7) Flag 3 SD outliers within each SMART_length group
% 8) Save results to txt and create correlation plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "3_SMART_vs_Generalization_results.txt");
plotOut   = fullfile(resultsDir, "3_SMART_vs_Generalization.png");

plotOutSlopeGen = fullfile(resultsDir, "3_SMART_Slope_1to6_vs_Generalization.png");

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

participants_s = unique(Participant_s);
nS = numel(participants_s);

viol = NaN(nS,1);
rt6_p = NaN(nS,1);
rt7_p = NaN(nS,1);
rtSlope_1to6_p = NaN(nS,1);
smart_len = strings(nS,1);

for i = 1:nS

    pid = participants_s(i);
    idx = Participant_s == pid;

    rt_i = RT(idx);
    blk_i = Block(idx);
    smart_i = SMART_s(idx);

    smart_len(i) = smart_i(1);

    % RT6, RT7, and violation cost
    if any(blk_i == 6)
        rt6_p(i) = mean(rt_i(blk_i == 6), "omitnan");
    end

    if any(blk_i == 7)
        rt7_p(i) = mean(rt_i(blk_i == 7), "omitnan");
    end

    if ~isnan(rt6_p(i)) && ~isnan(rt7_p(i))
        viol(i) = rt7_p(i) - rt6_p(i);
    end

    % RT learning slope across Blocks 1-6
    rt_by_block_1to6 = NaN(6,1);

    for b = 1:6
        if any(blk_i == b)
            rt_by_block_1to6(b) = mean(rt_i(blk_i == b), "omitnan");
        end
    end

    validSlope = ~isnan(rt_by_block_1to6);

    slopeFit = polyfit(find(validSlope), rt_by_block_1to6(validSlope), 1);
    rtSlope_1to6_p(i) = slopeFit(1);
end

smartSummary = table(participants_s, smart_len, rt6_p, rt7_p, viol, rtSlope_1to6_p, ...
    'VariableNames', {'ParticipantID','SMART_length','RT6','RT7','ViolationCost','RTSlope_1to6'});

participants_g = unique(Participant_g);
nG = numel(participants_g);

gen_mean = NaN(nG,1);
smart_len_g = strings(nG,1);

for i = 1:nG

    pid = participants_g(i);
    idx = Participant_g == pid;

    cat_i = Category(idx);
    cor_i = Correct(idx);
    smart_i = SMART_g(idx);

    smart_len_g(i) = smart_i(1);

    uni_idx = cat_i == "uni";
    multi_idx = cat_i == "multi";

    gen_uni_i = mean(cor_i(uni_idx) == 1, "omitnan") * 100;
    gen_multi_i = mean(cor_i(multi_idx) == 1, "omitnan") * 100;

    gen_mean(i) = mean([gen_uni_i, gen_multi_i], "omitnan");
end

genSummary = table(participants_g, smart_len_g, gen_mean, ...
    'VariableNames', {'ParticipantID','SMART_length','GenMean'});

M = innerjoin(smartSummary, genSummary, 'Keys', {'ParticipantID','SMART_length'});

conditions = ["ms0", "ms250", "ms500", "ms1100"];

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [0.85 0.33 0.10];
condColors('ms250')  = [0.10 0.35 0.85];
condColors('ms500')  = [0.10 0.65 0.20];
condColors('ms1100') = [0.85 0.10 0.10];

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "SMART vs GENERALIZATION (WITHIN-CONDITION)\n");
fprintf(fid, "=========================================\n\n");

figure('Position',[200 300 1200 350]);

xMin = floor(min(M.ViolationCost, [], "omitnan"));
xMax = ceil(max(M.ViolationCost, [], "omitnan"));
yMin = floor(min(M.GenMean, [], "omitnan"));
yMax = ceil(max(M.GenMean, [], "omitnan"));

r_slope_store = NaN(numel(conditions),1);
p_slope_store = NaN(numel(conditions),1);

for c = 1:numel(conditions)

    cond = conditions(c);
    idx = M.SMART_length == cond;
    Mc = M(idx,:);

    % Correlations
    % Does the link between SMART behavior and generalization weaken as ISI increases?

    [r_mean, p_mean] = corr(Mc.ViolationCost, Mc.GenMean, ...
        'Rows','complete', 'Type','Pearson');

    [r_rt6_mean, p_rt6_mean] = corr(Mc.RT6, Mc.GenMean, ...
        'Rows','complete', 'Type','Pearson');

    [r_slope_mean, p_slope_mean] = corr(Mc.RTSlope_1to6, Mc.GenMean, ...
        'Rows','complete', 'Type','Pearson');

    % FDR correction within condition across the correlation family
    p_corr_raw = [
        p_mean
        p_rt6_mean
        p_slope_mean
    ];

    p_corr_fdr = NaN(size(p_corr_raw));
    validP = ~isnan(p_corr_raw);

    if any(validP)
        pvals = p_corr_raw(validP);
        [p_sorted, sortIdx] = sort(pvals(:));
        m = numel(p_sorted);

        p_fdr_sorted = p_sorted .* m ./ (1:m)';

        for ii = m-1:-1:1
            p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
        end

        p_fdr_sorted = min(p_fdr_sorted, 1);

        p_fdr_valid = NaN(size(pvals(:)));
        p_fdr_valid(sortIdx) = p_fdr_sorted;

        p_corr_fdr(validP) = p_fdr_valid;
    end

    % Assign FDR-corrected p-values back to readable variables
    p_mean_fdr       = p_corr_fdr(1);   % Violation vs GenMean
    p_rt6_mean_fdr   = p_corr_fdr(2);   % RT6 vs GenMean
    p_slope_mean_fdr = p_corr_fdr(3);   % Slope vs GenMean

    r_slope_store(c) = r_slope_mean;
    p_slope_store(c) = p_slope_mean_fdr;

    % Outliers within condition
    % A participant is flagged if any Part 3 variable is > 3 SD from
    % the condition mean.
    
    zSlope = (Mc.RTSlope_1to6 - mean(Mc.RTSlope_1to6, "omitnan")) ./ std(Mc.RTSlope_1to6, "omitnan");
    zRT6   = (Mc.RT6          - mean(Mc.RT6,          "omitnan")) ./ std(Mc.RT6,          "omitnan");
    zViol  = (Mc.ViolationCost - mean(Mc.ViolationCost, "omitnan")) ./ std(Mc.ViolationCost, "omitnan");
    zMean  = (Mc.GenMean       - mean(Mc.GenMean,       "omitnan")) ./ std(Mc.GenMean,       "omitnan");
    
    outSlope = abs(zSlope) > 3;
    outRT6   = abs(zRT6)   > 3;
    outViol  = abs(zViol)  > 3;
    outMean  = abs(zMean)  > 3;

    fprintf(fid, "Condition: %s\n", cond);
    fprintf(fid, "==============================\n");
    fprintf(fid, "n = %d\n\n", height(Mc));

    fprintf(fid, "ID    Slope_1-6(ms/block)   RT6(ms)   RT7(ms)   Viol_7-6(ms)   GenMean(%%)\n");
    for i = 1:height(Mc)
        fprintf(fid, "%s   %18.2f   %7.2f   %7.2f   %10.2f   %8.2f\n", ...
            Mc.ParticipantID(i), Mc.RTSlope_1to6(i), Mc.RT6(i), Mc.RT7(i), Mc.ViolationCost(i), Mc.GenMean(i));
    end

    fprintf(fid, "\n");

    fprintf(fid, "CORRELATIONS\n");
    fprintf(fid, "Pearson  | RT6 vs GenMean        | r = %.3f | p = %.4f | p_FDR = %.4f\n", ...
        r_rt6_mean, p_rt6_mean, p_rt6_mean_fdr);

    fprintf(fid, "Pearson  | Slope 1-6 vs GenMean  | r = %.3f | p = %.4f | p_FDR = %.4f\n", ...
        r_slope_mean, p_slope_mean, p_slope_mean_fdr);

    fprintf(fid, "Pearson  | Violation vs GenMean   | r = %.3f | p = %.4f | p_FDR = %.4f\n", ...
        r_mean, p_mean, p_mean_fdr);
    fprintf(fid, "\n");

    fprintf(fid, "3 SD OUTLIER CHECK\n");
    
    fprintf(fid, "Potential outliers in Slope_1-6: ");
    if any(outSlope)
        rows = find(outSlope);
        for ii = 1:numel(rows)
            pid = string(Mc.ParticipantID(rows(ii)));
            fprintf(fid, "%s ", pid);
        end
    else
        fprintf(fid, "None");
    end
    fprintf(fid, "\n");
    
    fprintf(fid, "Potential outliers in RT6: ");
    if any(outRT6)
        rows = find(outRT6);
        for ii = 1:numel(rows)
            pid = string(Mc.ParticipantID(rows(ii)));
            fprintf(fid, "%s ", pid);
        end
    else
        fprintf(fid, "None");
    end
    fprintf(fid, "\n");
    
    fprintf(fid, "Potential outliers in ViolationCost: ");
    if any(outViol)
        rows = find(outViol);
        for ii = 1:numel(rows)
            pid = string(Mc.ParticipantID(rows(ii)));
            fprintf(fid, "%s ", pid);
        end
    else
        fprintf(fid, "None");
    end
    fprintf(fid, "\n");
    
    fprintf(fid, "Potential outliers in GenMean: ");
    if any(outMean)
        rows = find(outMean);
        for ii = 1:numel(rows)
            pid = string(Mc.ParticipantID(rows(ii)));
            fprintf(fid, "%s ", pid);
        end
    else
        fprintf(fid, "None");
    end
    fprintf(fid, "\n\n");

    subplot(1,4,c)
    hold on

    thisColor = condColors(char(cond));

    scatter(Mc.ViolationCost, Mc.GenMean, 45, thisColor, 'filled');

    for i = 1:height(Mc)
        text(Mc.ViolationCost(i) + 1, Mc.GenMean(i), Mc.ParticipantID(i), 'FontSize', 6);
    end

    x = Mc.ViolationCost;
    y = Mc.GenMean;
    ok = isfinite(x) & isfinite(y);

    if sum(ok) >= 2
        b = polyfit(x(ok), y(ok), 1);
        xfit = linspace(min(x(ok)), max(x(ok)), 100);
        yfit = polyval(b, xfit);
        plot(xfit, yfit, 'k-', 'LineWidth', 1.5);
    end

    xlabel('Violation cost (ms)', 'FontSize', 8);
    ylabel('Generalization mean (%)', 'FontSize', 8);

    cleanCond = erase(cond, "ms");
    title(cleanCond + " ms: r = " + sprintf('%.3f', r_mean) + ...
          ", p_FDR = " + sprintf('%.4f', p_mean_fdr), ...
          'Interpreter','none','FontSize',9);

    xlim([xMin xMax]);
    ylim([yMin yMax]);

    box off
    set(gca,'FontSize',7);
    hold off
end

[p_rt6_anova, ~, stats_rt6_anova] = anova1(M.RT6, M.SMART_length, 'off');
fprintf(fid, "\nRT6 ACROSS CONDITIONS\n");
fprintf(fid, "-----------------------------------\n");
fprintf(fid, "ANOVA p = %.4f\n\n", p_rt6_anova);

if p_rt6_anova < 0.05
    rt6_posthoc = multcompare(stats_rt6_anova, 'Display', 'off');
    rt6_pairwise_p = rt6_posthoc(:,6);

    rt6_pairwise_p_fdr = NaN(size(rt6_pairwise_p));
    valid = ~isnan(rt6_pairwise_p);

    if any(valid)
        pvals = rt6_pairwise_p(valid);
        [p_sorted, sortIdx] = sort(pvals);
        m = numel(p_sorted);

        p_fdr_sorted = p_sorted .* m ./ (1:m)';

        for ii = m-1:-1:1
            p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
        end

        p_fdr_sorted = min(p_fdr_sorted, 1);

        tmp = NaN(size(pvals));
        tmp(sortIdx) = p_fdr_sorted;
        rt6_pairwise_p_fdr(valid) = tmp;
    end

    fprintf(fid, "\nRT6 POST-HOC COMPARISONS\n");
    fprintf(fid, "-----------------------------------\n");

    for i = 1:size(rt6_posthoc,1)
        g1 = conditions(rt6_posthoc(i,1));
        g2 = conditions(rt6_posthoc(i,2));

        fprintf(fid, "%s vs %s | p = %.4f | p_FDR = %.4f\n", ...
            g1, g2, rt6_posthoc(i,6), rt6_pairwise_p_fdr(i));
    end
end

fprintf(fid, "RT SLOPE (BLOCKS 1-6) ACROSS CONDITIONS\n");
fprintf(fid, "-----------------------------------\n");
slope_all = M.RTSlope_1to6;
group_all = M.SMART_length;

valid = ~isnan(slope_all);
slope_all = slope_all(valid);
group_all = group_all(valid);

[p_anova, ~, stats_anova] = anova1(slope_all, group_all, 'off');
fprintf(fid, "ANOVA p = %.4f\n", p_anova);

if p_anova < 0.05

    c_mult_anova = multcompare(stats_anova, 'Display','off');
    pairwise_p = c_mult_anova(:,6);

    % FDR correction for ANOVA post-hoc comparisons
    pairwise_p_fdr = NaN(size(pairwise_p));
    valid = ~isnan(pairwise_p);

    if any(valid)
        pvals = pairwise_p(valid);
        [p_sorted, sortIdx] = sort(pvals);
        m = numel(p_sorted);

        p_fdr_sorted = p_sorted .* m ./ (1:m)';

        for ii = m-1:-1:1
            p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
        end

        p_fdr_sorted = min(p_fdr_sorted,1);

        tmp = NaN(size(pvals));
        tmp(sortIdx) = p_fdr_sorted;
        pairwise_p_fdr(valid) = tmp;
    end

    fprintf(fid, "ANOVA post-hoc comparisons:\n");
    for i = 1:size(c_mult_anova,1)
        fprintf(fid, "%s vs %s | p = %.4f | p_FDR = %.4f\n", ...
            conditions(c_mult_anova(i,1)), ...
            conditions(c_mult_anova(i,2)), ...
            c_mult_anova(i,6), ...
            pairwise_p_fdr(i));
    end
end

fclose(fid);
saveas(gcf, plotOut);
close

% Plot RT slope Blocks 1-6 vs Generalization by condition
figure('Position',[200 300 1200 350]);

for c = 1:numel(conditions)

    cond = conditions(c);
    idx = M.SMART_length == cond;
    Mc = M(idx,:);


    subplot(1,4,c)
    hold on

    thisColor = condColors(char(cond));

    scatter(Mc.RTSlope_1to6, Mc.GenMean, 45, thisColor, 'filled');

    for i = 1:height(Mc)
        text(Mc.RTSlope_1to6(i) + 0.5, Mc.GenMean(i), Mc.ParticipantID(i), 'FontSize', 6);
    end

    x = Mc.RTSlope_1to6;
    y = Mc.GenMean;
    ok = isfinite(x) & isfinite(y);

    if sum(ok) >= 2
        b = polyfit(x(ok), y(ok), 1);
        xfit = linspace(min(x(ok)), max(x(ok)), 100);
        yfit = polyval(b, xfit);
        plot(xfit, yfit, 'k-', 'LineWidth', 1.5);
    end

    xlabel('RT slope Blocks 1-6 (ms/block)', 'FontSize', 8);
    ylabel('GenMean (%)', 'FontSize', 8);

    cleanCond = erase(cond, "ms");
    title(cleanCond + " ms: r = " + sprintf('%.3f', r_slope_store(c)) + ...
          ", p_FDR = " + sprintf('%.4f', p_slope_store(c)), ...
          'Interpreter','none','FontSize',9);

    box off
    set(gca,'FontSize',7);
    hold off
end

saveas(gcf, plotOutSlopeGen);
close



%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Fourth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level table:
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - Mean RT across preprocessed SMART trials
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) For each SMART_length group:
%    - Compute partial correlation between ViolationCost and GenMean,
%      controlling for MeanRT
%    - Apply FDR correction across the four partial correlations
% 4) Save results to txt
% 5) Plot residualized relationship separately for each condition
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "4_SMART_specificity_results.txt");
plotOut   = fullfile(resultsDir, "4_SMART_specificity_results.png");

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

conditions = ["ms0", "ms250", "ms500", "ms1100"];

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [0.85 0.33 0.10];
condColors('ms250')  = [0.10 0.35 0.85];
condColors('ms500')  = [0.10 0.65 0.20];
condColors('ms1100') = [0.85 0.10 0.10];

participants_s = unique(Participant_s);
nS = numel(participants_s);

viol = NaN(nS,1);
meanRT = NaN(nS,1);
smart_len = strings(nS,1);

for i = 1:nS

    pid = participants_s(i);
    idx = Participant_s == pid;

    rt_i = RT(idx);
    blk_i = Block(idx);
    smart_i = SMART_s(idx);

    smart_len(i) = smart_i(1);

    meanRT(i) = mean(rt_i, "omitnan");

    if any(blk_i == 6) && any(blk_i == 7)
        rt6 = mean(rt_i(blk_i == 6), "omitnan");
        rt7 = mean(rt_i(blk_i == 7), "omitnan");
        viol(i) = rt7 - rt6;
    end
end

smartSummary = table(participants_s, smart_len, viol, meanRT, ...
    'VariableNames', {'ParticipantID','SMART_length','ViolationCost','MeanRT'});

participants_g = unique(Participant_g);
nG = numel(participants_g);

gen_mean = NaN(nG,1);
smart_len_g = strings(nG,1);

for i = 1:nG

    pid = participants_g(i);
    idx = Participant_g == pid;

    cat_i = Category(idx);
    cor_i = Correct(idx);
    smart_i = SMART_g(idx);

    smart_len_g(i) = smart_i(1);

    uni_idx = cat_i == "uni";
    multi_idx = cat_i == "multi";

    uni = mean(cor_i(uni_idx) == 1, "omitnan");
    multi = mean(cor_i(multi_idx) == 1, "omitnan");

    gen_mean(i) = mean([uni, multi], "omitnan") * 100;
end

genSummary = table(participants_g, smart_len_g, gen_mean, ...
    'VariableNames', {'ParticipantID','SMART_length','GenMean'});

M = innerjoin(smartSummary, genSummary, 'Keys', {'ParticipantID','SMART_length'});

r_partial_all = NaN(numel(conditions),1);
p_partial_all = NaN(numel(conditions),1);
n_partial_all = NaN(numel(conditions),1);

resV_all = cell(numel(conditions),1);
resG_all = cell(numel(conditions),1);
Mc_all = cell(numel(conditions),1);

for c = 1:numel(conditions)

    cond = conditions(c);
    idx = M.SMART_length == cond;
    Mc = M(idx,:);

    Mc_all{c} = Mc;

    okModel = isfinite(Mc.ViolationCost) & isfinite(Mc.GenMean) & isfinite(Mc.MeanRT);

    X = [ones(sum(okModel),1), Mc.MeanRT(okModel)];

    beta_v = X \ Mc.ViolationCost(okModel);
    res_v = Mc.ViolationCost(okModel) - X * beta_v;

    beta_g = X \ Mc.GenMean(okModel);
    res_g = Mc.GenMean(okModel) - X * beta_g;

    res_v_full = NaN(height(Mc),1);
    res_g_full = NaN(height(Mc),1);

    res_v_full(okModel) = res_v;
    res_g_full(okModel) = res_g;

    resV_all{c} = res_v_full;
    resG_all{c} = res_g_full;

    [r_partial, p_partial] = partialcorr(Mc.ViolationCost, Mc.GenMean, Mc.MeanRT, ...
        'Rows','complete', 'Type','Pearson');

    r_partial_all(c) = r_partial;
    p_partial_all(c) = p_partial;
    n_partial_all(c) = sum(okModel);
end

[p_sorted, sortIdx] = sort(p_partial_all);
m = numel(p_sorted);

p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);

p_partial_fdr = NaN(size(p_partial_all));
p_partial_fdr(sortIdx) = p_fdr_sorted;

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "SPECIFICITY ANALYSIS (WITHIN-CONDITION)\n");
fprintf(fid, "======================================\n\n");
fprintf(fid, "Input SMART file: %s\n", smartFile);
fprintf(fid, "Input Generalization file: %s\n\n", genFile);

for c = 1:numel(conditions)

    cond = conditions(c);
    Mc = Mc_all{c};

    fprintf(fid, "Condition: %s\n", cond);
    fprintf(fid, "==============================\n");
    fprintf(fid, "n = %d\n\n", height(Mc));

    fprintf(fid, "PARTICIPANT TABLE\n");
    fprintf(fid, "ID    Viol_7-6(ms)   MeanRT(ms)   GenMean(%%)\n");

    for i = 1:height(Mc)
        fprintf(fid, "%s   %10.2f   %10.2f   %8.2f\n", ...
            Mc.ParticipantID(i), Mc.ViolationCost(i), Mc.MeanRT(i), Mc.GenMean(i));
    end

    fprintf(fid, "\n");

    fprintf(fid, "PARTIAL CORRELATION\n");
    fprintf(fid, "Pearson  | Violation vs GenMean controlling for MeanRT | r = %.3f | p = %.4f | p_FDR = %.4f\n\n", ...
        r_partial_all(c), p_partial_all(c), p_partial_fdr(c));
end

all_res_v = vertcat(resV_all{:});
all_res_g = vertcat(resG_all{:});

xMin = floor(min(all_res_v, [], "omitnan"));
xMax = ceil(max(all_res_v, [], "omitnan"));
yMin = floor(min(all_res_g, [], "omitnan"));
yMax = ceil(max(all_res_g, [], "omitnan"));

figure('Position',[180 250 1200 340]);

for c = 1:numel(conditions)

    cond = conditions(c);
    Mc = Mc_all{c};

    res_v = resV_all{c};
    res_g = resG_all{c};

    subplot(1,4,c)
    hold on

    thisColor = condColors(char(cond));

    scatter(res_v, res_g, 45, thisColor, 'filled');

    for i = 1:height(Mc)
        if isfinite(res_v(i)) && isfinite(res_g(i))
            text(res_v(i) + 0.5, res_g(i), Mc.ParticipantID(i), 'FontSize', 6);
        end
    end

    ok = isfinite(res_v) & isfinite(res_g);

    if sum(ok) >= 2
        b = polyfit(res_v(ok), res_g(ok), 1);
        xfit = linspace(min(res_v(ok)), max(res_v(ok)), 100);
        yfit = polyval(b, xfit);
        plot(xfit, yfit, 'k-', 'LineWidth', 1.5);
    end

    xlabel('Violation residual (MeanRT removed)', 'FontSize', 8);
    ylabel('GenMean residual (MeanRT removed)', 'FontSize', 8);

    cleanCond = erase(cond, "ms");
    title(cleanCond + " ms: r = " + sprintf('%.3f', r_partial_all(c)) + ...
          ", p_FDR = " + sprintf('%.4f', p_partial_fdr(c)), ...
          'Interpreter','none','FontSize',9);

    xlim([xMin xMax]);
    ylim([yMin yMax]);

    box off
    set(gca,'FontSize',7);
    hold off
end

saveas(gcf, plotOut);
close

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Fifth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level table:
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
%    - SMART_length group
% 3) Center ViolationCost
% 4) Fit full interaction model:
%    GenMean ~ ViolationCost_c * SMART_length
%    - Report model coefficients with FDR-corrected p-values
% 5) Fit reduced no-interaction model:
%    GenMean ~ ViolationCost_c + SMART_length
% 6) Compare full vs reduced model to test the interaction
% 7) Compute Cook's Distance from the full interaction model
% 8) Refit full and reduced models without high-influence participants
% 9) Save original, clean, and comparison results to txt
% 10) Plot original and clean interaction regression models
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "5_SMART_violation_regression_results.txt");

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

participants_s = unique(Participant_s);
nS = numel(participants_s);

viol = NaN(nS,1);
smart_len = strings(nS,1);

for i = 1:nS
    pid = participants_s(i);
    idx = Participant_s == pid;

    rt_i = RT(idx);
    blk_i = Block(idx);
    smart_i = SMART_s(idx);

    smart_len(i) = smart_i(1);

    if any(blk_i == 6) && any(blk_i == 7)
        rt6 = mean(rt_i(blk_i == 6), "omitnan");
        rt7 = mean(rt_i(blk_i == 7), "omitnan");
        viol(i) = rt7 - rt6;
    end
end

smartSummary = table(participants_s, smart_len, viol, ...
    'VariableNames', {'ParticipantID','SMART_length','ViolationCost'});

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

participants_g = unique(Participant_g);
nG = numel(participants_g);

gen_mean = NaN(nG,1);
smart_len_g = strings(nG,1);

for i = 1:nG
    pid = participants_g(i);
    idx = Participant_g == pid;

    cat_i = Category(idx);
    cor_i = Correct(idx);
    smart_i = SMART_g(idx);

    smart_len_g(i) = smart_i(1);

    uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
    multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

    gen_mean(i) = mean([uni, multi], "omitnan") * 100;
end

genSummary = table(participants_g, smart_len_g, gen_mean, ...
    'VariableNames', {'ParticipantID','SMART_length','GenMean'});

M = innerjoin(smartSummary, genSummary, 'Keys', {'ParticipantID','SMART_length'});

% Force ms0 as reference group
M.SMART_length = categorical(M.SMART_length, ...
    ["ms0","ms250","ms500","ms1100"], ...
    ["ms0","ms250","ms500","ms1100"]);

% Original model
M.ViolationCost_c = M.ViolationCost - mean(M.ViolationCost, "omitnan");
mdl = fitlm(M, 'GenMean ~ ViolationCost_c * SMART_length');
coefNames = mdl.CoefficientNames;
interactionIdx = contains(coefNames, ':ViolationCost_c');

% Reduced model without the interaction
mdl_noInteraction = fitlm(M, 'GenMean ~ ViolationCost_c + SMART_length');

% Influence check
influence = mdl.Diagnostics.CooksDistance;
threshold = 4 / height(M);
highInfluenceIdx = find(influence > threshold);

% Clean model
M_clean = M(influence <= threshold, :);
M_clean.ViolationCost_c = M_clean.ViolationCost - mean(M_clean.ViolationCost, "omitnan");
mdl_clean = fitlm(M_clean, 'GenMean ~ ViolationCost_c * SMART_length');

mdl_clean_noInteraction = fitlm(M_clean, 'GenMean ~ ViolationCost_c + SMART_length');

% Original model interaction test using SSE comparison
SSE_full = mdl.SSE;
SSE_reduced = mdl_noInteraction.SSE;

df_full = mdl.DFE;
df_reduced = mdl_noInteraction.DFE;

df1 = df_reduced - df_full;
df2 = df_full;

F_interaction = ((SSE_reduced - SSE_full) / df1) / (SSE_full / df2);
p_interaction = 1 - fcdf(F_interaction, df1, df2);

% Clean model interaction test using SSE comparison
SSE_full_clean = mdl_clean.SSE;
SSE_reduced_clean = mdl_clean_noInteraction.SSE;

df_full_clean = mdl_clean.DFE;
df_reduced_clean = mdl_clean_noInteraction.DFE;

df1_clean = df_reduced_clean - df_full_clean;
df2_clean = df_full_clean;

F_interaction_clean = ((SSE_reduced_clean - SSE_full_clean) / df1_clean) / ...
                      (SSE_full_clean / df2_clean);
p_interaction_clean = 1 - fcdf(F_interaction_clean, df1_clean, df2_clean);

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "INTERACTION MODEL RESULTS\n");
fprintf(fid, "=========================\n\n");

fprintf(fid, "ANALYSIS SETUP\n");
fprintf(fid, "--------------\n");
fprintf(fid, "Outcome: GenMean\n");
fprintf(fid, "Predictor: ViolationCost_c\n");
fprintf(fid, "Grouping variable: SMART_length\n");
fprintf(fid, "Reference group: ms0\n");
fprintf(fid, "Full model: GenMean ~ ViolationCost_c * SMART_length\n");
fprintf(fid, "Reduced model: GenMean ~ ViolationCost_c + SMART_length\n\n");

fprintf(fid, "ORIGINAL MODEL FIT\n");
fprintf(fid, "------------------\n");

fprintf(fid, "FULL ORIGINAL MODEL\n");
fprintf(fid, "n = %d\n", height(M));
fprintf(fid, "R^2 = %.4f\n", mdl.Rsquared.Ordinary);
fprintf(fid, "Adjusted R^2 = %.4f\n", mdl.Rsquared.Adjusted);
fprintf(fid, "Model F-statistic = %.4f\n", mdl.ModelFitVsNullModel.Fstat);
fprintf(fid, "Model p-value = %.4f\n\n", mdl.ModelFitVsNullModel.Pvalue);

fprintf(fid, "REDUCED ORIGINAL MODEL\n");
fprintf(fid, "R^2 = %.4f\n", mdl_noInteraction.Rsquared.Ordinary);
fprintf(fid, "Adjusted R^2 = %.4f\n\n", mdl_noInteraction.Rsquared.Adjusted);

fprintf(fid, "Number of coefficients (full model): %d\n", ...
    numel(mdl.CoefficientNames));

fprintf(fid, "Number of coefficients (reduced model): %d\n\n", ...
    numel(mdl_noInteraction.CoefficientNames));

fprintf(fid, "ORIGINAL INTERACTION TEST\n");
fprintf(fid, "-------------------------\n");
fprintf(fid, "Interaction terms tested:\n");
for i = 1:numel(coefNames)
    if interactionIdx(i)
        fprintf(fid, "  %s\n", coefNames{i});
    end
end
fprintf(fid, "df1 (constraints) = %d\n", df1);
fprintf(fid, "df2 (residual) = %d\n", df2);
fprintf(fid, "Full model SSE = %.4f\n", SSE_full);
fprintf(fid, "Reduced model SSE = %.4f\n", SSE_reduced);
fprintf(fid, "SSE improvement = %.4f\n", SSE_reduced - SSE_full);
fprintf(fid, "Interaction test: F = %.4f | df1 = %d | df2 = %d | p = %.4f\n\n", ...
    F_interaction, df1, df2, p_interaction);

fprintf(fid, "ORIGINAL COEFFICIENTS\n");
fprintf(fid, "---------------------\n");
coefTable = mdl.Coefficients;
for i = 1:height(coefTable)
    rowName = coefTable.Properties.RowNames{i};
    if strcmp(rowName, '(Intercept)')
        fprintf(fid, "%s | Estimate = %.4f | t = %.3f | p = %.4f\n", ...
            rowName, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
    else
        fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
            rowName, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
    end
end
fprintf(fid, "\n");

fprintf(fid, "FDR-CORRECTED ORIGINAL COEFFICIENTS\n");
fprintf(fid, "-----------------------------------\n");

coefNames_orig = coefTable.Properties.RowNames;

keepIdx_orig = ~strcmp(coefNames_orig, '(Intercept)');

pvals_orig = coefTable.pValue(keepIdx_orig);
terms_orig = coefNames_orig(keepIdx_orig);

[p_sorted, sortIdx] = sort(pvals_orig);

m_orig = numel(p_sorted);

p_fdr_sorted = p_sorted .* m_orig ./ (1:m_orig)';

for ii = m_orig-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);

p_fdr_orig = NaN(size(pvals_orig));
p_fdr_orig(sortIdx) = p_fdr_sorted;

fprintf(fid, "%-45s %-12s %-12s\n", ...
    "Term", "p", "p_FDR");

for i = 1:numel(terms_orig)

    fprintf(fid, "%-45s %-12.6f %-12.6f\n", ...
        string(terms_orig{i}), ...
        pvals_orig(i), ...
        p_fdr_orig(i));

end

fprintf(fid, "\n");

fprintf(fid, "INFLUENCE DIAGNOSTICS\n");
fprintf(fid, "---------------------\n");
fprintf(fid, "Cook's Distance threshold (4/n) = %.4f\n", threshold);
fprintf(fid, "Max Cook's D = %.4f\n", max(influence));
fprintf(fid, "Number of high-influence participants = %d\n", numel(highInfluenceIdx));

if isempty(highInfluenceIdx)
    fprintf(fid, "High-influence participants: None\n\n");
else
    fprintf(fid, "High-influence participants:\n");
    for i = 1:numel(highInfluenceIdx)
        idx = highInfluenceIdx(i);
        pid_full = string(M.ParticipantID(idx));
        fprintf(fid, "%s | %s | Cook's D = %.4f\n", ...
            pid_full, string(M.SMART_length(idx)), influence(idx));
    end
    fprintf(fid, "\n");
end

fprintf(fid, "CLEAN MODEL FIT\n");
fprintf(fid, "---------------\n");

fprintf(fid, "FULL CLEAN MODEL\n");
fprintf(fid, "n = %d\n", height(M_clean));
fprintf(fid, "Removed = %d\n", numel(highInfluenceIdx));
fprintf(fid, "R^2 = %.4f\n", mdl_clean.Rsquared.Ordinary);
fprintf(fid, "Adjusted R^2 = %.4f\n", mdl_clean.Rsquared.Adjusted);
fprintf(fid, "Model F-statistic = %.4f\n", mdl_clean.ModelFitVsNullModel.Fstat);
fprintf(fid, "Model p-value = %.4f\n\n", mdl_clean.ModelFitVsNullModel.Pvalue);

fprintf(fid, "REDUCED CLEAN MODEL\n");
fprintf(fid, "R^2 = %.4f\n", mdl_clean_noInteraction.Rsquared.Ordinary);
fprintf(fid, "Adjusted R^2 = %.4f\n\n", mdl_clean_noInteraction.Rsquared.Adjusted);

fprintf(fid, "CLEAN INTERACTION TEST\n");
fprintf(fid, "----------------------\n");
fprintf(fid, "Full clean model SSE = %.4f\n", SSE_full_clean);
fprintf(fid, "Reduced clean model SSE = %.4f\n", SSE_reduced_clean);
fprintf(fid, "SSE improvement clean = %.4f\n", SSE_reduced_clean - SSE_full_clean);
fprintf(fid, "Interaction test clean: F = %.4f | df1 = %d | df2 = %d | p = %.4f\n\n", ...
    F_interaction_clean, df1_clean, df2_clean, p_interaction_clean);

fprintf(fid, "CLEAN COEFFICIENTS\n");
fprintf(fid, "------------------\n");
coefTable_clean = mdl_clean.Coefficients;
for i = 1:height(coefTable_clean)
    rowName = coefTable_clean.Properties.RowNames{i};
    if strcmp(rowName, '(Intercept)')
        fprintf(fid, "%s | Estimate = %.4f | t = %.3f | p = %.4f\n", ...
            rowName, coefTable_clean.Estimate(i), coefTable_clean.tStat(i), coefTable_clean.pValue(i));
    else
        fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
            rowName, coefTable_clean.Estimate(i), coefTable_clean.tStat(i), coefTable_clean.pValue(i));
    end
end
fprintf(fid, "\n");

fprintf(fid, "FDR-CORRECTED CLEAN COEFFICIENTS\n");
fprintf(fid, "--------------------------------\n");

coefNames_clean2 = coefTable_clean.Properties.RowNames;

keepIdx_clean = ~strcmp(coefNames_clean2, '(Intercept)');

pvals_clean = coefTable_clean.pValue(keepIdx_clean);
terms_clean = coefNames_clean2(keepIdx_clean);

[p_sorted, sortIdx] = sort(pvals_clean);

m_clean = numel(p_sorted);

p_fdr_sorted = p_sorted .* m_clean ./ (1:m_clean)';

for ii = m_clean-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);

p_fdr_clean = NaN(size(pvals_clean));
p_fdr_clean(sortIdx) = p_fdr_sorted;

fprintf(fid, "%-45s %-12s %-12s\n", ...
    "Term", "p", "p_FDR");

for i = 1:numel(terms_clean)

    fprintf(fid, "%-45s %-12.6f %-12.6f\n", ...
        string(terms_clean{i}), ...
        pvals_clean(i), ...
        p_fdr_clean(i));

end

fprintf(fid, "\n");

fprintf(fid, "COMPARISON: ORIGINAL vs CLEAN\n");
fprintf(fid, "-----------------------------\n");

orig_rows = coefTable.Properties.RowNames;
clean_rows = coefTable_clean.Properties.RowNames;
shared_rows = intersect(orig_rows, clean_rows, 'stable');

for i = 1:numel(shared_rows)
    rn = shared_rows{i};
    idx1 = strcmp(orig_rows, rn);
    idx2 = strcmp(clean_rows, rn);

    est1 = coefTable.Estimate(idx1);
    p1   = coefTable.pValue(idx1);

    est2 = coefTable_clean.Estimate(idx2);
    p2   = coefTable_clean.pValue(idx2);

    fprintf(fid, "%s\n", rn);
    fprintf(fid, "  Original | Estimate = %.4f | p = %.4f\n", est1, p1);
    fprintf(fid, "  Clean    | Estimate = %.4f | p = %.4f\n\n", est2, p2);
end
fclose(fid);

% Plot with two panels: original model and clean model
plotOut = fullfile(resultsDir, "5_SMART_violation_regression_comparison.png");

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [0.95 0.60 0.10];
condColors('ms250')  = [0.10 0.35 0.85];
condColors('ms500')  = [0.10 0.65 0.20];
condColors('ms1100') = [0.85 0.10 0.10];

groups = ["ms0","ms250","ms500","ms1100"];

% Common axes across both panels
xAll = [M.ViolationCost; M_clean.ViolationCost];
yAll = [M.GenMean; M_clean.GenMean];

xMin = floor(min(xAll, [], "omitnan"));
xMax = ceil(max(xAll, [], "omitnan"));
yMin = floor(min(yAll, [], "omitnan"));
yMax = ceil(max(yAll, [], "omitnan"));

figure('Position',[180 250 1200 420]);

subplot(1,2,1)
hold on

h1 = gobjects(numel(groups),1);

for g = 1:numel(groups)
    grp = groups(g);
    idx = string(M.SMART_length) == grp;

    x = M.ViolationCost(idx);
    y = M.GenMean(idx);

    thisColor = condColors(char(grp));

    scatter(x, y, 35, thisColor, 'filled');

    if any(idx)
        x_line = linspace(min(x), max(x), 100)';
        Tpred = table;
        Tpred.ViolationCost = x_line;
        Tpred.SMART_length = categorical(repmat(grp, numel(x_line), 1), ...
            ["ms0","ms250","ms500","ms1100"], ["ms0","ms250","ms500","ms1100"]);
        Tpred.ViolationCost_c = x_line - mean(M.ViolationCost, "omitnan");

        y_line = predict(mdl, Tpred);
        h1(g) = plot(x_line, y_line, 'Color', thisColor, 'LineWidth', 2);
    end
end

xlabel('Violation cost (ms)', 'FontSize', 9);
ylabel('Generalization mean (%)', 'FontSize', 9);
title('Original model', 'FontSize', 10);

xlim([xMin xMax]);
ylim([yMin yMax]);

legend(h1, {'0 ms','250 ms','500 ms','1100 ms'}, 'Location','southeast', 'FontSize', 8);

box off
set(gca,'FontSize',8)
hold off

subplot(1,2,2)
hold on

h2 = gobjects(numel(groups),1);

for g = 1:numel(groups)
    grp = groups(g);
    idx = string(M_clean.SMART_length) == grp;

    x = M_clean.ViolationCost(idx);
    y = M_clean.GenMean(idx);

    thisColor = condColors(char(grp));

    scatter(x, y, 35, thisColor, 'filled');

    if any(idx)
        x_line = linspace(min(x), max(x), 100)';
        Tpred = table;
        Tpred.ViolationCost = x_line;
        Tpred.SMART_length = categorical(repmat(grp, numel(x_line), 1), ...
            ["ms0","ms250","ms500","ms1100"], ["ms0","ms250","ms500","ms1100"]);
        Tpred.ViolationCost_c = x_line - mean(M_clean.ViolationCost, "omitnan");

        y_line = predict(mdl_clean, Tpred);
        h2(g) = plot(x_line, y_line, 'Color', thisColor, 'LineWidth', 2);
    end
end

xlabel('Violation cost (ms)', 'FontSize', 9);
ylabel('Generalization mean (%)', 'FontSize', 9);
title('Without high-influence participants', 'FontSize', 10);

xlim([xMin xMax]);
ylim([yMin yMax]);

legend(h2, {'0 ms','250 ms','500 ms','1100 ms'}, 'Location','southeast', 'FontSize', 8);

box off
set(gca,'FontSize',8)
hold off

saveas(gcf, plotOut);
close

% %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % SMART Excel Analyzer - Sixth Part
% % 1) Load preprocessed SMART and Generalization datasets
% % 2) Build participant-level table:
% %    - RT slope across Blocks 1–6
% %    - GenMean = mean(UNI accuracy, MULTI accuracy)
% %    - SMART_length group
% % 3) Center RT slope
% % 4) Fit full interaction model:
% %    GenMean ~ Slope_c * SMART_length
% % 5) Report model fit, coefficients, and FDR-corrected coefficient p-values
% % 6) Compute Cook's Distance from the full slope model
% % 7) Refit and recenter full model after removing high-influence participants
% % 8) Save original and clean model results to txt
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% clear;
% clc;
% 
% baseDir = "D:\Data\SMART";
% resultsDir = fullfile(baseDir, "results");
% genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
% smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
% txtOut    = fullfile(resultsDir, "6_SMART_slope_regression_result.txt");
% 
% Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
% Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");
% 
% RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
% Block = str2double(erase(string(Ts.("block")), "'"));
% Participant_s = erase(string(Ts.("Participant Private ID")), "'");
% SMART_s = string(Ts.("SMART_length"));
% 
% participants_s = unique(Participant_s);
% nS = numel(participants_s);
% 
% slope = NaN(nS,1);
% smart_len = strings(nS,1);
% 
% for i = 1:nS
% 
%     pid = participants_s(i);
%     idx = Participant_s == pid;
% 
%     rt_i = RT(idx);
%     blk_i = Block(idx);
%     smart_i = SMART_s(idx);
% 
%     smart_len(i) = smart_i(1);
% 
%     blocks = 1:6;
%     rt_block = NaN(6,1);
% 
%     for b = 1:6
%         idxBlock = blk_i == b;
%         if any(idxBlock)
%             rt_block(b) = mean(rt_i(idxBlock), "omitnan");
%         end
%     end
% 
%     validBlocks = ~isnan(rt_block);
% 
%     if sum(validBlocks) >= 3
%         pfit = polyfit(blocks(validBlocks), rt_block(validBlocks)', 1);
%         slope(i) = pfit(1);
%     end
% end
% 
% smartSummary = table(participants_s, smart_len, slope, ...
%     'VariableNames', {'ParticipantID','SMART_length','Slope'});
% 
% Participant_g = erase(string(Tg.("Participant Private ID")), "'");
% SMART_g = string(Tg.("SMART_length"));
% Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
% Correct = str2double(erase(string(Tg.("Correct")), "'"));
% 
% participants_g = unique(Participant_g);
% nG = numel(participants_g);
% 
% gen_mean = NaN(nG,1);
% smart_len_g = strings(nG,1);
% 
% for i = 1:nG
% 
%     pid = participants_g(i);
%     idx = Participant_g == pid;
% 
%     cat_i = Category(idx);
%     cor_i = Correct(idx);
%     smart_i = SMART_g(idx);
% 
%     smart_len_g(i) = smart_i(1);
% 
%     uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
%     multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");
% 
%     gen_mean(i) = mean([uni, multi], "omitnan") * 100;
% end
% 
% genSummary = table(participants_g, smart_len_g, gen_mean, ...
%     'VariableNames', {'ParticipantID','SMART_length','GenMean'});
% 
% M = innerjoin(smartSummary, genSummary, ...
%     'Keys', {'ParticipantID','SMART_length'});
% 
% M.SMART_length = categorical(M.SMART_length, ...
%     ["ms0","ms250","ms500","ms1100"], ...
%     ["ms0","ms250","ms500","ms1100"]);
% 
% M.Slope_c = M.Slope - mean(M.Slope, "omitnan");
% 
% mdl = fitlm(M, 'GenMean ~ Slope_c * SMART_length');
% 
% fid = fopen(txtOut, 'w');
% if fid == -1
%     error("Could not open txt output file: %s", txtOut);
% end
% 
% fprintf(fid, "RT SLOPE MODEL RESULTS\n");
% fprintf(fid, "======================\n\n");
% fprintf(fid, "Model: GenMean ~ Slope_c * SMART_length\n");
% fprintf(fid, "Reference group: ms0\n");
% fprintf(fid, "n = %d\n\n", height(M));
% 
% fprintf(fid, "MODEL FIT\n");
% fprintf(fid, "R^2 = %.4f\n", mdl.Rsquared.Ordinary);
% fprintf(fid, "Adjusted R^2 = %.4f\n", mdl.Rsquared.Adjusted);
% fprintf(fid, "Model F-statistic = %.4f\n", mdl.ModelFitVsNullModel.Fstat);
% fprintf(fid, "Model p-value = %.4f\n\n", mdl.ModelFitVsNullModel.Pvalue);
% 
% fprintf(fid, "COEFFICIENTS\n");
% 
% coefTable = mdl.Coefficients;
% 
% for i = 1:height(coefTable)
%     name = coefTable.Properties.RowNames{i};
%     fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
%         name, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
% end
% 
% fprintf(fid, "\nFDR-CORRECTED COEFFICIENTS\n");
% fprintf(fid, "==========================\n\n");
% 
% coefNames = coefTable.Properties.RowNames;
% 
% keepIdx = ~strcmp(coefNames, '(Intercept)');
% 
% pvals = coefTable.pValue(keepIdx);
% terms = coefNames(keepIdx);
% 
% [p_sorted, sortIdx] = sort(pvals);
% 
% m = numel(p_sorted);
% 
% p_fdr_sorted = p_sorted .* m ./ (1:m)';
% 
% for ii = m-1:-1:1
%     p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
% end
% 
% p_fdr_sorted = min(p_fdr_sorted, 1);
% 
% p_fdr = NaN(size(pvals));
% p_fdr(sortIdx) = p_fdr_sorted;
% 
% fprintf(fid, "%-40s %-12s %-12s\n", ...
%     "Term", "p", "p_FDR");
% 
% for i = 1:numel(terms)
% 
%     fprintf(fid, "%-40s %-12.6f %-12.6f\n", ...
%         string(terms{i}), ...
%         pvals(i), ...
%         p_fdr(i));
% 
% end
% 
% % Cook's distance for full slope model
% fprintf(fid, "\nCOOK'S DISTANCE CHECK\n");
% fprintf(fid, "=====================\n\n");
% 
% cookD = mdl.Diagnostics.CooksDistance;
% cookThreshold = 4 / height(M);
% 
% highCook = cookD > cookThreshold;
% nHighCook = sum(highCook);
% maxCook = max(cookD);
% 
% fprintf(fid, "Cook's D threshold: 4/n = %.4f\n", cookThreshold);
% fprintf(fid, "High-influence participants = %d\n", nHighCook);
% fprintf(fid, "Max Cook's D = %.4f\n\n", maxCook);
% 
% fprintf(fid, "High-influence participant list\n");
% fprintf(fid, "%-20s %-10s %-12s %-12s %-12s\n", ...
%     "ParticipantID", "ISI", "Slope", "GenMean", "CookD");
% 
% for i = 1:height(M)
%     if highCook(i)
%         fprintf(fid, "%-20s %-10s %-12.4f %-12.4f %-12.4f\n", ...
%             string(M.ParticipantID(i)), ...
%             string(M.SMART_length(i)), ...
%             M.Slope(i), ...
%             M.GenMean(i), ...
%             cookD(i));
%     end
% end
% 
% % Refit full model after removing high-influence participants
% fprintf(fid, "\nCLEAN FULL MODEL AFTER COOK'S D REMOVAL\n");
% fprintf(fid, "=======================================\n\n");
% 
% M_clean = M(~highCook,:);
% M_clean.Slope_c = M_clean.Slope - mean(M_clean.Slope, "omitnan");
% mdl_clean = fitlm(M_clean, 'GenMean ~ Slope_c * SMART_length');
% 
% fprintf(fid, "Model: GenMean ~ Slope_c * SMART_length\n");
% fprintf(fid, "n original = %d\n", height(M));
% fprintf(fid, "n clean = %d\n\n", height(M_clean));
% 
% fprintf(fid, "MODEL FIT\n");
% fprintf(fid, "R^2 = %.4f\n", mdl_clean.Rsquared.Ordinary);
% fprintf(fid, "Adjusted R^2 = %.4f\n", mdl_clean.Rsquared.Adjusted);
% fprintf(fid, "Model F-statistic = %.4f\n", mdl_clean.ModelFitVsNullModel.Fstat);
% fprintf(fid, "Model p-value = %.4f\n\n", mdl_clean.ModelFitVsNullModel.Pvalue);
% 
% fprintf(fid, "COEFFICIENTS\n");
% 
% coefTableClean = mdl_clean.Coefficients;
% 
% for i = 1:height(coefTableClean)
% 
%     name = coefTableClean.Properties.RowNames{i};
% 
%     fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
%         name, ...
%         coefTableClean.Estimate(i), ...
%         coefTableClean.tStat(i), ...
%         coefTableClean.pValue(i));
% 
% end
% 
% fprintf(fid, "\nFDR-CORRECTED CLEAN COEFFICIENTS\n");
% fprintf(fid, "================================\n\n");
% 
% coefNamesClean = coefTableClean.Properties.RowNames;
% 
% keepIdxClean = ~strcmp(coefNamesClean, '(Intercept)');
% 
% pvalsClean = coefTableClean.pValue(keepIdxClean);
% termsClean = coefNamesClean(keepIdxClean);
% 
% [p_sorted, sortIdx] = sort(pvalsClean);
% 
% m_clean = numel(p_sorted);
% 
% p_fdr_sorted = p_sorted .* m_clean ./ (1:m_clean)';
% 
% for ii = m_clean-1:-1:1
%     p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
% end
% 
% p_fdr_sorted = min(p_fdr_sorted, 1);
% 
% p_fdr_clean = NaN(size(pvalsClean));
% p_fdr_clean(sortIdx) = p_fdr_sorted;
% 
% fprintf(fid, "%-40s %-12s %-12s\n", ...
%     "Term", "p", "p_FDR");
% 
% for i = 1:numel(termsClean)
% 
%     fprintf(fid, "%-40s %-12.6f %-12.6f\n", ...
%         string(termsClean{i}), ...
%         pvalsClean(i), ...
%         p_fdr_clean(i));
% 
% end
% 
% fclose(fid);

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Seventh Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level table:
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
%    - SMART_length group
% 3) Center ViolationCost
% 4) Fit robust full interaction model:
%    GenMean ~ ViolationCost_c * SMART_length
% 5) Fit robust reduced model:
%    GenMean ~ ViolationCost_c + SMART_length
% 6) Compare robust full vs reduced interaction models
%    - R²
%    - Adjusted R²
%    - Approximate SSE-based interaction test
% 7) Save robust model coefficients and FDR-corrected coefficient p-values
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "7_SMART_robust_regression_results.txt");

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

participants_s = unique(Participant_s);
nS = numel(participants_s);

viol = NaN(nS,1);
smart_len = strings(nS,1);

for i = 1:nS
    pid = participants_s(i);
    idx = Participant_s == pid;

    rt_i = RT(idx);
    blk_i = Block(idx);
    smart_i = SMART_s(idx);

    smart_len(i) = smart_i(1);

    if any(blk_i == 6) && any(blk_i == 7)
        rt6 = mean(rt_i(blk_i == 6), "omitnan");
        rt7 = mean(rt_i(blk_i == 7), "omitnan");
        viol(i) = rt7 - rt6;
    end
end

smartSummary = table(participants_s, smart_len, viol, ...
    'VariableNames', {'ParticipantID','SMART_length','ViolationCost'});

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

participants_g = unique(Participant_g);
nG = numel(participants_g);

gen_mean = NaN(nG,1);
smart_len_g = strings(nG,1);

for i = 1:nG
    pid = participants_g(i);
    idx = Participant_g == pid;

    cat_i = Category(idx);
    cor_i = Correct(idx);
    smart_i = SMART_g(idx);

    smart_len_g(i) = smart_i(1);

    uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
    multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

    gen_mean(i) = mean([uni, multi], "omitnan") * 100;
end

genSummary = table(participants_g, smart_len_g, gen_mean, ...
    'VariableNames', {'ParticipantID','SMART_length','GenMean'});

M = innerjoin(smartSummary, genSummary, ...
    'Keys', {'ParticipantID','SMART_length'});

M.SMART_length = categorical(M.SMART_length, ...
    ["ms0","ms250","ms500","ms1100"], ...
    ["ms0","ms250","ms500","ms1100"]);

M.ViolationCost_c = M.ViolationCost - mean(M.ViolationCost, "omitnan");

mdl_full = fitlm(M, 'GenMean ~ ViolationCost_c * SMART_length', 'RobustOpts','on');
mdl_reduced = fitlm(M, 'GenMean ~ ViolationCost_c + SMART_length', 'RobustOpts','on');

y = M.GenMean;

yhat_full = predict(mdl_full, M);
SSE_full = sum((y - yhat_full).^2, "omitnan");
SST = sum((y - mean(y, "omitnan")).^2, "omitnan");
R2_full = 1 - (SSE_full / SST);

yhat_reduced = predict(mdl_reduced, M);
SSE_reduced = sum((y - yhat_reduced).^2, "omitnan");
R2_reduced = 1 - (SSE_reduced / SST);

% Adjusted R2 for robust full and reduced models
n = height(M);

p_full = numel(mdl_full.CoefficientNames) - 1;
p_reduced = numel(mdl_reduced.CoefficientNames) - 1;

adjR2_full = 1 - ((1 - R2_full) * (n - 1) / (n - p_full - 1));
adjR2_reduced = 1 - ((1 - R2_reduced) * (n - 1) / (n - p_reduced - 1));

% Robust interaction test using SSE comparison
df1 = p_full - p_reduced;
df2 = n - p_full - 1;

F_interaction = ((SSE_reduced - SSE_full) / df1) / ...
                (SSE_full / df2);

p_interaction = 1 - fcdf(F_interaction, df1, df2);

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file");
end

fprintf(fid, "ROBUST REGRESSION RESULTS\n");
fprintf(fid, "=========================\n\n");

fprintf(fid, "MODEL FIT\n");
fprintf(fid, "--------------\n");
fprintf(fid, "n = %d\n\n", height(M));

fprintf(fid, "FULL ROBUST MODEL\n");
fprintf(fid, "Model: GenMean ~ ViolationCost_c * SMART_length\n");
fprintf(fid, "R^2 = %.4f\n", R2_full);
fprintf(fid, "Adjusted R^2 = %.4f\n", adjR2_full);
fprintf(fid, "Number of coefficients = %d\n\n", numel(mdl_full.CoefficientNames));

fprintf(fid, "REDUCED ROBUST MODEL\n");
fprintf(fid, "Model: GenMean ~ ViolationCost_c + SMART_length\n");
fprintf(fid, "R^2 = %.4f\n", R2_reduced);
fprintf(fid, "Adjusted R^2 = %.4f\n", adjR2_reduced);
fprintf(fid, "Number of coefficients = %d\n\n", numel(mdl_reduced.CoefficientNames));

fprintf(fid, "ROBUST INTERACTION TEST\n");
fprintf(fid, "-----------------------\n");
fprintf(fid, "Full model SSE = %.4f\n", SSE_full);
fprintf(fid, "Reduced model SSE = %.4f\n", SSE_reduced);
fprintf(fid, "SSE improvement = %.4f\n", SSE_reduced - SSE_full);
fprintf(fid, "Interaction test: F = %.4f | df1 = %d | df2 = %d | p = %.4f\n\n", ...
    F_interaction, df1, df2, p_interaction);

fprintf(fid, "FULL MODEL COEFFICIENTS\n");
fprintf(fid, "--------------\n");
coefTable = mdl_full.Coefficients;

for i = 1:height(coefTable)
    name = coefTable.Properties.RowNames{i};
    fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
        name, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
end

fprintf(fid, "\nFDR-CORRECTED FULL MODEL COEFFICIENTS\n");
fprintf(fid, "-------------------------------------\n");

coefNames_full = coefTable.Properties.RowNames;

keepIdx_full = ~strcmp(coefNames_full, '(Intercept)');

pvals_full = coefTable.pValue(keepIdx_full);
terms_full = coefNames_full(keepIdx_full);

[p_sorted, sortIdx] = sort(pvals_full);

m_full = numel(p_sorted);

p_fdr_sorted = p_sorted .* m_full ./ (1:m_full)';

for ii = m_full-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);

p_fdr_full = NaN(size(pvals_full));
p_fdr_full(sortIdx) = p_fdr_sorted;

fprintf(fid, "%-45s %-12s %-12s\n", ...
    "Term", "p", "p_FDR");

for i = 1:numel(terms_full)

    fprintf(fid, "%-45s %-12.6f %-12.6f\n", ...
        string(terms_full{i}), ...
        pvals_full(i), ...
        p_fdr_full(i));

end

fprintf(fid, "\n");

fprintf(fid, "REDUCED MODEL COEFFICIENTS\n");
fprintf(fid, "--------------\n");

coefTable_reduced = mdl_reduced.Coefficients;

for i = 1:height(coefTable_reduced)
    name = coefTable_reduced.Properties.RowNames{i};
    fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
        name, coefTable_reduced.Estimate(i), coefTable_reduced.tStat(i), coefTable_reduced.pValue(i));
end

fprintf(fid, "\nFDR-CORRECTED REDUCED MODEL COEFFICIENTS\n");
fprintf(fid, "----------------------------------------\n");

coefNames_reduced = coefTable_reduced.Properties.RowNames;

keepIdx_reduced = ~strcmp(coefNames_reduced, '(Intercept)');

pvals_reduced = coefTable_reduced.pValue(keepIdx_reduced);
terms_reduced = coefNames_reduced(keepIdx_reduced);

[p_sorted, sortIdx] = sort(pvals_reduced);

m_reduced = numel(p_sorted);

p_fdr_sorted = p_sorted .* m_reduced ./ (1:m_reduced)';

for ii = m_reduced-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);

p_fdr_reduced = NaN(size(pvals_reduced));
p_fdr_reduced(sortIdx) = p_fdr_sorted;

fprintf(fid, "%-45s %-12s %-12s\n", ...
    "Term", "p", "p_FDR");

for i = 1:numel(terms_reduced)

    fprintf(fid, "%-45s %-12.6f %-12.6f\n", ...
        string(terms_reduced{i}), ...
        pvals_reduced(i), ...
        p_fdr_reduced(i));

end
fclose(fid);

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Eighth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level table:
%    - Violation cost: RT(Block 7) - RT(Block 6)
%    - Mean RT across preprocessed SMART trials
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
%    - SMART_length group
% 3) Within each SMART_length group, fit robust regression:
%    GenMean ~ ViolationCost + MeanRT
% 4) Extract ViolationCost and MeanRT coefficient p-values from each condition
% 5) Apply FDR correction separately across:
%    - the four ViolationCost coefficient tests
%    - the four MeanRT coefficient tests
% 6) Save model fit, coefficients, p-values, and FDR-corrected p-values to txt
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "8_SMART_RT_control_results.txt");

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile,   "VariableNamingRule","preserve", "TextType","string");

RT = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

participants_s = unique(Participant_s);
nS = numel(participants_s);

viol = NaN(nS,1);
meanRT = NaN(nS,1);
smart_len = strings(nS,1);

for i = 1:nS
    pid = participants_s(i);
    idx = Participant_s == pid;

    rt_i = RT(idx);
    blk_i = Block(idx);
    smart_i = SMART_s(idx);

    smart_len(i) = smart_i(1);

    % Mean RT across all valid SMART trials
    meanRT(i) = mean(rt_i, "omitnan");

    % Violation = block 7 - block 6
    if any(blk_i == 6) && any(blk_i == 7)
        rt6 = mean(rt_i(blk_i == 6), "omitnan");
        rt7 = mean(rt_i(blk_i == 7), "omitnan");
        viol(i) = rt7 - rt6;
    end
end

smartSummary = table(participants_s, smart_len, viol, meanRT, ...
    'VariableNames', {'ParticipantID','SMART_length','ViolationCost','MeanRT'});

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

participants_g = unique(Participant_g);
nG = numel(participants_g);

gen_mean = NaN(nG,1);
smart_len_g = strings(nG,1);

for i = 1:nG
    pid = participants_g(i);
    idx = Participant_g == pid;

    cat_i = Category(idx);
    cor_i = Correct(idx);
    smart_i = SMART_g(idx);

    smart_len_g(i) = smart_i(1);

    uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
    multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

    gen_mean(i) = mean([uni, multi], "omitnan") * 100;
end

genSummary = table(participants_g, smart_len_g, gen_mean, ...
    'VariableNames', {'ParticipantID','SMART_length','GenMean'});

M = innerjoin(smartSummary, genSummary, 'Keys', {'ParticipantID','SMART_length'});

conditions = ["ms0", "ms250", "ms500", "ms1100"];
p_violation = NaN(numel(conditions),1);
p_meanRT = NaN(numel(conditions),1);

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "RT-CONTROL ROBUST REGRESSION ANALYSIS\n");
fprintf(fid, "====================================\n\n");
fprintf(fid, "Model per condition: GenMean ~ ViolationCost + MeanRT\n");
fprintf(fid, "Robust regression used in all conditions\n\n");
fprintf(fid, "INTERPRETATION TARGET\n");
fprintf(fid, "This analysis tests if ViolationCost predicts GenMean within each ISI condition after controlling for MeanRT.\n");
fprintf(fid, "FDR correction is applied separately across the four ViolationCost tests and the four MeanRT tests.\n\n");

for c = 1:numel(conditions)

    cond = conditions(c);
    idx = string(M.SMART_length) == cond;
    Mc = M(idx,:);

    fprintf(fid, "Condition: %s\n", cond);
    fprintf(fid, "==============================\n");
    fprintf(fid, "n = %d\n", height(Mc));

    if height(Mc) < 5
        fprintf(fid, "Not enough data\n\n");
        continue;
    end

    mdl = fitlm(Mc, 'GenMean ~ ViolationCost + MeanRT', 'RobustOpts', 'on');

    fprintf(fid, "MODEL FIT\n");
    fprintf(fid, "R^2 = %.4f\n", mdl.Rsquared.Ordinary);

    fprintf(fid, "Adjusted R^2 = %.4f\n", mdl.Rsquared.Adjusted);
    fprintf(fid, "Model F-statistic = %.4f\n", mdl.ModelFitVsNullModel.Fstat);
    fprintf(fid, "Model p-value = %.4f\n\n", mdl.ModelFitVsNullModel.Pvalue);

    fprintf(fid, "COEFFICIENTS\n");
    coefTable = mdl.Coefficients;

    violRow = strcmp(coefTable.Properties.RowNames, 'ViolationCost');
    if any(violRow)
        p_violation(c) = coefTable.pValue(violRow);
    end

    if any(strcmp(coefTable.Properties.RowNames, 'MeanRT'))
    
        meanRTRow = strcmp(coefTable.Properties.RowNames, 'MeanRT');
        p_meanRT(c) = coefTable.pValue(meanRTRow);
    
    end

    for i = 1:height(coefTable)
        rowName = coefTable.Properties.RowNames{i};
        if strcmp(rowName, '(Intercept)')
            fprintf(fid, "%s | Estimate = %.4f | t = %.3f | p = %.4f\n", ...
                rowName, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
        else
            fprintf(fid, "%s | Beta = %.4f | t = %.3f | p = %.4f\n", ...
                rowName, coefTable.Estimate(i), coefTable.tStat(i), coefTable.pValue(i));
        end
    end

    fprintf(fid, "\n");
end

% FDR correction for ViolationCost coefficient across conditions
validP = ~isnan(p_violation);
pvals = p_violation(validP);

p_violation_fdr = NaN(size(p_violation));

if ~isempty(pvals)

    [p_sorted, sortIdx] = sort(pvals(:));
    m = numel(p_sorted);

    p_fdr_sorted = p_sorted .* m ./ (1:m)';

    for ii = m-1:-1:1
        p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
    end

    p_fdr_sorted = min(p_fdr_sorted, 1);

    p_fdr_valid = NaN(size(pvals(:)));
    p_fdr_valid(sortIdx) = p_fdr_sorted;

    p_violation_fdr(validP) = p_fdr_valid;
end

fprintf(fid, "FDR CORRECTION FOR VIOLATIONCOST COEFFICIENT\n");
fprintf(fid, "============================================\n");
for c = 1:numel(conditions)
    fprintf(fid, "%s | p = %.4f | p_FDR = %.4f\n", ...
        conditions(c), p_violation(c), p_violation_fdr(c));
end
fprintf(fid, "\n");

% FDR correction for MeanRT coefficient across conditions
validP = ~isnan(p_meanRT);
pvals = p_meanRT(validP);

p_meanRT_fdr = NaN(size(p_meanRT));

if ~isempty(pvals)

    [p_sorted, sortIdx] = sort(pvals(:));
    m = numel(p_sorted);

    p_fdr_sorted = p_sorted .* m ./ (1:m)';

    for ii = m-1:-1:1
        p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
    end

    p_fdr_sorted = min(p_fdr_sorted, 1);

    p_fdr_valid = NaN(size(pvals(:)));
    p_fdr_valid(sortIdx) = p_fdr_sorted;

    p_meanRT_fdr(validP) = p_fdr_valid;

end

fprintf(fid, "FDR CORRECTION FOR MEANRT COEFFICIENT\n");
fprintf(fid, "=====================================\n");

for c = 1:numel(conditions)

    fprintf(fid, "%s | p = %.4f | p_FDR = %.4f\n", ...
        conditions(c), ...
        p_meanRT(c), ...
        p_meanRT_fdr(c));

end

fprintf(fid, "\n");

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Ninth Part
% 1) Load preprocessed Generalization dataset
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as learners:
%    - Learner = GenMean > 25%
% 4) Summarize learner and non-learner distributions by SMART_length group
% 5) Compare learner prevalence:
%    - Fisher exact tests: ms0 vs ms250, ms500, and ms1100
%    - FDR correction across the three pairwise tests
% 6) Compare learner-only GenMean across SMART_length groups:
%    - Kruskal-Wallis test
%    - Post-hoc comparisons only if test is significant
% 7) Save txt output and plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "9_SMART_learner_distribution_results.txt");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

Participant = erase(string(Tg.("Participant Private ID")), "'");
SMART = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];
chanceLevel = 25;
nCond = numel(conditions);

allGenMean = cell(nCond,1);
allLearnerFlag = cell(nCond,1);

learnerPct = NaN(nCond,1);
learnerMean_all = NaN(nCond,1);
nonLearnerMean_all = NaN(nCond,1);

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "LEARNER DISTRIBUTION RESULTS\n");
fprintf(fid, "============================\n\n");
fprintf(fid, "Learner definition: GenMean > 25%%\n");
fprintf(fid, "Chance level: 25%%\n");
fprintf(fid, "Purpose: quantify learner distribution and test whether learner prevalence and learner-only generalization differ across ISI conditions.\n\n");

for c = 1:nCond

    cond = conditions(c);
    idxCond = SMART == cond;

    Pcond = unique(Participant(idxCond));
    nP = numel(Pcond);

    genMean = NaN(nP,1);

    for i = 1:nP

        pid = Pcond(i);
        idx = idxCond & Participant == pid;

        cat_i = Category(idx);
        cor_i = Correct(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
        multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

        genMean(i) = mean([uni, multi], "omitnan") * 100;

    end

    learners = genMean > chanceLevel;

    nLearners = sum(learners);
    nNonLearners = nP - nLearners;

    pctLearners = (nLearners / nP) * 100;
    pctNonLearners = (nNonLearners / nP) * 100;

    learnerVals = genMean(learners);
    nonLearnerVals = genMean(~learners);

    if isempty(learnerVals)
        learnerMean = NaN;
        learnerSD = NaN;
        learnerMedian = NaN;
        learnerP25 = NaN;
        learnerP75 = NaN;
    else
        learnerMean = mean(learnerVals, "omitnan");
        learnerSD = std(learnerVals, "omitnan");
        learnerMedian = median(learnerVals, "omitnan");
        learnerP25 = prctile(learnerVals, 25);
        learnerP75 = prctile(learnerVals, 75);
    end

    if isempty(nonLearnerVals)
        nonLearnerMean = NaN;
        nonLearnerSD = NaN;
        nonLearnerMedian = NaN;
        nonLearnerP25 = NaN;
        nonLearnerP75 = NaN;
    else
        nonLearnerMean = mean(nonLearnerVals, "omitnan");
        nonLearnerSD = std(nonLearnerVals, "omitnan");
        nonLearnerMedian = median(nonLearnerVals, "omitnan");
        nonLearnerP25 = prctile(nonLearnerVals, 25);
        nonLearnerP75 = prctile(nonLearnerVals, 75);
    end

    allGenMean{c} = genMean;
    allLearnerFlag{c} = learners;

    learnerPct(c) = pctLearners;
    learnerMean_all(c) = learnerMean;
    nonLearnerMean_all(c) = nonLearnerMean;

    fprintf(fid, "Condition: %s\n", cond);
    fprintf(fid, "==============================\n");
    fprintf(fid, "Participants = %d\n", nP);
    fprintf(fid, "Learners = %d / %d (%.2f%%)\n", nLearners, nP, pctLearners);
    fprintf(fid, "Non-learners = %d / %d (%.2f%%)\n", nNonLearners, nP, pctNonLearners);

    fprintf(fid, "All participants GenMean:  mean = %.2f | SD = %.2f | median = %.2f\n", ...
        mean(genMean, "omitnan"), std(genMean, "omitnan"), median(genMean, "omitnan"));

    fprintf(fid, "Learners only GenMean:     mean = %.2f | SD = %.2f | median = %.2f | P25 = %.2f | P75 = %.2f\n", ...
        learnerMean, learnerSD, learnerMedian, learnerP25, learnerP75);

    fprintf(fid, "Non-learners only GenMean: mean = %.2f | SD = %.2f | median = %.2f | P25 = %.2f | P75 = %.2f\n\n", ...
        nonLearnerMean, nonLearnerSD, nonLearnerMedian, nonLearnerP25, nonLearnerP75);

end

learnerCounts = NaN(nCond,1);
nonLearnerCounts = NaN(nCond,1);

for c = 1:nCond
    learnerCounts(c) = sum(allLearnerFlag{c});
    nonLearnerCounts(c) = sum(~allLearnerFlag{c});
end

fprintf(fid, "\nLEARNER PROPORTION STATISTICS\n");
fprintf(fid, "=============================\n\n");
fprintf(fid, "Pairwise Fisher exact tests: ms0 vs each condition\n");

pairNames = ["ms250","ms500","ms1100"];
pairP = NaN(3,1);

for k = 1:3

    targetCond = pairNames(k);
    c2 = find(conditions == targetCond);

    fisherTable = [
        learnerCounts(1), nonLearnerCounts(1);
        learnerCounts(c2), nonLearnerCounts(c2)
    ];

    [~, p_fisher] = fishertest(fisherTable);

    pairP(k) = p_fisher;

    fprintf(fid, "ms0 vs %s | p = %.4f\n", targetCond, p_fisher);

end

p_fdr = NaN(size(pairP));
[p_sorted, sortIdx] = sort(pairP);
m = numel(p_sorted);

p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr(sortIdx) = p_fdr_sorted;

fprintf(fid, "\nPairwise Fisher tests with FDR correction:\n");

for k = 1:3
    fprintf(fid, "ms0 vs %s | p = %.4f | p_FDR = %.4f\n", ...
        pairNames(k), pairP(k), p_fdr(k));
end

learnerGen = [];
learnerGroup = strings(0,1);

for c = 1:nCond

    vals = allGenMean{c};
    flags = allLearnerFlag{c};

    valsLearners = vals(flags);
    valsLearners = valsLearners(~isnan(valsLearners));

    learnerGen = [learnerGen; valsLearners(:)];
    learnerGroup = [learnerGroup; repmat(conditions(c), numel(valsLearners), 1)];

end

[p_kw_learners, ~, stats_kw_learners] = kruskalwallis(learnerGen, learnerGroup, 'off');

fprintf(fid, "\nLEARNER-ONLY GENERALIZATION ACROSS CONDITIONS\n");
fprintf(fid, "============================================\n\n");
fprintf(fid, "Kruskal-Wallis test on learner-only GenMean: p = %.4f\n", p_kw_learners);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% POOLED LEARNER COMPARISON
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

vals_ms0 = allGenMean{1};
flags_ms0 = allLearnerFlag{1};
vals_ms0 = vals_ms0(flags_ms0);

vals_long = [];

for c = 2:nCond

    vals_tmp = allGenMean{c};
    flags_tmp = allLearnerFlag{c};

    vals_long = [vals_long; vals_tmp(flags_tmp)];

end

[p_pool, ~, stats_pool] = ranksum(vals_ms0, vals_long);

fprintf(fid, "\nPooled learner comparison: ms0 vs longer ISIs\n");
fprintf(fid, "ms0 learners mean = %.2f | SD = %.2f\n", ...
    mean(vals_ms0, "omitnan"), ...
    std(vals_ms0, "omitnan"));

fprintf(fid, "Longer ISI learners mean = %.2f | SD = %.2f\n", ...
    mean(vals_long, "omitnan"), ...
    std(vals_long, "omitnan"));

fprintf(fid, "Mann-Whitney U p = %.4f\n", p_pool);

if p_kw_learners < 0.05

    kw_posthoc = multcompare(stats_kw_learners, 'Display','off');

    fprintf(fid, "\nPost-hoc comparisons among learners:\n");

    for i = 1:size(kw_posthoc,1)

        g1 = string(stats_kw_learners.gnames{kw_posthoc(i,1)});
        g2 = string(stats_kw_learners.gnames{kw_posthoc(i,2)});
        pval = kw_posthoc(i,6);

        fprintf(fid, "%s vs %s | p = %.4f\n", g1, g2, pval);

    end

end

% Learner proportion by ISI

figure('Position',[300 300 650 430]);

condCat = categorical(conditions, conditions, 'Ordinal', true);

condColors = [
    0.85 0.33 0.10
    0.10 0.35 0.85
    0.10 0.65 0.20
    0.85 0.10 0.10
];

b = bar(condCat, learnerPct, 0.65);
b.FaceColor = 'flat';
% b.CData = [
%     0.25 0.25 0.25
%     0.50 0.50 0.50
%     0.50 0.50 0.50
%     0.50 0.50 0.50
% ];
b.CData = condColors;

ylabel('Learners (%)');
ylim([0 100]);
yticks(0:25:100);

title('Learner prevalence by ISI', 'Interpreter','none');

grid on
ax = gca;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;
ax.FontSize = 12;
ax.Box = 'off';

for c = 1:nCond
    text(c, learnerPct(c) + 4, ...
        sprintf('%.1f%%\n%d/%d', learnerPct(c), learnerCounts(c), ...
        learnerCounts(c) + nonLearnerCounts(c)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',11);
end

yline(50, '--', ...
    'LineWidth', 2, ...
    'Alpha', 0.35);

saveas(gcf, fullfile(resultsDir, "9_SMART_learner_distribution_learner_proportion.png"));
close;

% Mean GenMean by learner subgroup and ISI

figure('Position',[300 300 760 430]);

hold on;

x = 1:nCond;
barWidth = 0.34;

condColors = [
    0.85 0.33 0.10
    0.10 0.35 0.85
    0.10 0.65 0.20
    0.85 0.10 0.10
];

for c = 1:nCond
    bar(x(c) - barWidth/2, learnerMean_all(c), barWidth, ...
        'FaceColor', condColors(c,:), ...
        'EdgeColor', 'none');

    bar(x(c) + barWidth/2, nonLearnerMean_all(c), barWidth, ...
        'FaceColor', condColors(c,:), ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.35);
end

hChance = yline(chanceLevel, '--k', ...
    'LineWidth', 1.2, ...
    'Alpha', 0.45);

ylabel('GenMean (%)');
ylim([0 70]);
yticks(0:10:70);

xticks(x);
xticklabels(conditions);

title('Generalization by learner subgroup', 'Interpreter','none');

grid on
ax = gca;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;
ax.FontSize = 12;
ax.Box = 'off';

for c = 1:nCond
    text(x(c) - barWidth/2, learnerMean_all(c) + 2, ...
        sprintf('%.1f', learnerMean_all(c)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',10);

    text(x(c) + barWidth/2, nonLearnerMean_all(c) + 2, ...
        sprintf('%.1f', nonLearnerMean_all(c)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',10);
end

hLearner = bar(nan, nan, ...
    'FaceColor', [0.45 0.45 0.45], ...
    'EdgeColor', 'none');

hNonLearner = bar(nan, nan, ...
    'FaceColor', [0.45 0.45 0.45], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.35);

legend([hLearner hNonLearner hChance], ...
    {'Learners','Non-learners','Chance'}, ...
    'Location','northoutside', ...
    'Orientation','horizontal', ...
    'Box','off');

hold off;

saveas(gcf, fullfile(resultsDir, "9_SMART_learner_distribution_group_means.png"));
close;

% Violin plot
figure('Position',[300 300 950 420]);
hold on;

condColors = containers.Map('KeyType','char','ValueType','any');
condColors('ms0')    = [0.85 0.33 0.10];
condColors('ms250')  = [0.10 0.35 0.85];
condColors('ms500')  = [0.10 0.65 0.20];
condColors('ms1100') = [0.85 0.10 0.10];

densityBandwidth = 0.35;
violinWidth = 0.18;

condX = 1:1.6:(1 + 1.6*(numel(conditions)-1));
offsets = [-0.40, 0, 0.40];

for c = 1:numel(conditions)

    thisColor = condColors(char(conditions(c)));

    vals_all = allGenMean{c};
    vals_all = vals_all(~isnan(vals_all));

    learnerFlag = allLearnerFlag{c};

    vals_learn = vals_all(learnerFlag);
    vals_non = vals_all(~learnerFlag);

    groups = {vals_non, vals_all, vals_learn};
    alphas = [0.15, 0.35, 0.55];

    for g = 1:3

        vals = groups{g};

        if numel(vals) < 4
            continue
        end

        xpos = condX(c) + offsets(g);

        [f, xi] = ksdensity(vals, 'Support',[0 100], 'Bandwidth', densityBandwidth);
        f = f / max(f);
        f = f * violinWidth;

        fill([xpos - f, fliplr(xpos + f)], ...
             [xi, fliplr(xi)], ...
             thisColor, ...
             'EdgeColor', thisColor, ...
             'FaceAlpha', alphas(g));

        xj = xpos + (rand(size(vals)) - 0.5) * 0.08;

        scatter(xj, vals, 22, ...
            'MarkerFaceColor', [0.7 0.7 0.7], ...
            'MarkerFaceAlpha', 0.30, ...
            'MarkerEdgeColor', [0.35 0.35 0.35], ...
            'MarkerEdgeAlpha', 0.60);

        medVal = median(vals, "omitnan");

        plot([xpos - violinWidth, xpos + violinWidth], ...
             [medVal medVal], ...
             'k-', 'LineWidth', 1.5);

    end

end

xPositions = [];
xLabels = strings(0,1);

for c = 1:numel(conditions)

    xPositions = [xPositions, condX(c) + offsets];

    xLabels = [xLabels; ...
        "Non-learners"; ...
        "All"; ...
        "Learners"];

end

xlim([condX(1)-0.85, condX(end)+0.85]);
xticks(xPositions);
xticklabels(xLabels);
xtickangle(45);

hCond = gobjects(numel(conditions),1);

for c = 1:numel(conditions)

    thisColor = condColors(char(conditions(c)));

    hCond(c) = patch(nan, nan, thisColor, ...
        'FaceAlpha', 0.45, ...
        'EdgeColor', thisColor);

end

legend(hCond, {'ms0','ms250','ms500','ms1100'}, ...
    'Location','northeastoutside');

title('GenMean distribution by learner subgroup', 'Interpreter','none');
ylabel('GenMean (%)');
ylim([0 100]);

box off
grid on
set(gca,'FontSize',10);

hold off;

saveas(gcf, fullfile(resultsDir, "9_SMART_learner_distribution_split_violins.png"));
close;

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Tenth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level variables:
%    - GenMean
%    - Learner status
%    - ViolationCost
% 3) Test learner probability models:
%    - Logistic regression: Learner ~ ISI
%    - Logistic regression: Learner ~ ISI + Violation
%    - Odds ratios
% 4) Test learner-only GenMean models:
%    - OLS: GenMean ~ ISI
%    - OLS: GenMean ~ ISI + Violation
%    - Nested model comparison
%    - Standardized Violation model
%    - Interaction model
%    - Robust regression
% 5) Compute Cook's Distance for learner-only OLS model
% 6) Apply FDR correction within each model/test family
% 7) Save txt output
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");
genFile   = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");
txtOut    = fullfile(resultsDir, "10_SMART_two_part_learner_model_results.txt");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");
Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");

RT_s = str2double(erase(string(Ts.("Reaction Time")), "'"));
Block_s = str2double(erase(string(Ts.("block")), "'"));
Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));

Participant = erase(string(Tg.("Participant Private ID")), "'");
SMART = string(Tg.("SMART_length"));
Category = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct = str2double(erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];
chanceLevel = 25;
nCond = numel(conditions);

GenMean_all = [];
Violation_all = [];
Learner_all = [];
ISI_all = strings(0,1);
Participant_all = strings(0,1);

for c = 1:nCond

    cond = conditions(c);
    idxCond = SMART == cond;

    Pcond = unique(Participant(idxCond));
    nP = numel(Pcond);

    genMean = NaN(nP,1);
    violCost = NaN(nP,1);

    for i = 1:nP

        pid = Pcond(i);
        idx = idxCond & Participant == pid;

        cat_i = Category(idx);
        cor_i = Correct(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
        multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

        genMean(i) = mean([uni, multi], "omitnan") * 100;

        idxSmart = SMART_s == cond & Participant_s == pid;

        rt_i = RT_s(idxSmart);
        blk_i = Block_s(idxSmart);

        if any(blk_i == 6) && any(blk_i == 7)
            rt6 = mean(rt_i(blk_i == 6), "omitnan");
            rt7 = mean(rt_i(blk_i == 7), "omitnan");
            violCost(i) = rt7 - rt6;
        end

    end

    learners = genMean > chanceLevel;

    GenMean_all = [GenMean_all; genMean(:)];
    Violation_all = [Violation_all; violCost(:)];
    Learner_all = [Learner_all; learners(:)];
    Participant_all = [Participant_all; Pcond(:)];
    ISI_all = [ISI_all; repmat(cond, nP, 1)];

end

valid = ~isnan(GenMean_all) & ~isnan(Violation_all);

GenMean_all = GenMean_all(valid);
Violation_all = Violation_all(valid);
Learner_all = Learner_all(valid);
ISI_all = ISI_all(valid);
Participant_all = Participant_all(valid);

ISI_cat = categorical(ISI_all, conditions, 'Ordinal', false);

tblAll = table(Participant_all, Learner_all, GenMean_all, ISI_cat, Violation_all, ...
    'VariableNames', {'ParticipantID','Learner','GenMean','ISI','Violation'});

fid = fopen(txtOut, 'w');
if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "TWO-PART LEARNER-STATE ANALYSIS\n");
fprintf(fid, "===============================\n\n");

fprintf(fid, "ANALYSIS SETUP\n");
fprintf(fid, "--------------\n");
fprintf(fid, "Learner definition: GenMean > 25%%\n");
fprintf(fid, "Part A outcome: Learner status\n");
fprintf(fid, "Part B outcome: Learner-only GenMean\n");
fprintf(fid, "Reference group: ms0\n\n");
fprintf(fid, "FDR correction is applied within each model/test family.\n\n");

% PART A - LEARNER PROBABILITY
fprintf(fid, "PART A - LEARNER PROBABILITY\n");
fprintf(fid, "============================\n\n");

% Logistic model 1: ISI only
mdl_learner_isi = fitglm(tblAll, 'Learner ~ ISI', 'Distribution','binomial');

fprintf(fid, "LOGISTIC MODEL: LEARNER ~ ISI\n");
fprintf(fid, "-----------------------------\n");
printCoefTable(fid, mdl_learner_isi.Coefficients);
fprintf(fid, "\n");

p_learner_isi = mdl_learner_isi.Coefficients.pValue(2:end);
terms_learner_isi = mdl_learner_isi.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_learner_isi);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_learner_isi = NaN(size(p_learner_isi));
p_fdr_learner_isi(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: LEARNER ~ ISI\n");
fprintf(fid, "-----------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_learner_isi)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_learner_isi{i}), ...
        p_learner_isi(i), ...
        p_fdr_learner_isi(i));
end

fprintf(fid, "\n");

% Logistic model 2: ISI + Violation
mdl_learner_isi_viol = fitglm(tblAll, ...
    'Learner ~ ISI + Violation', ...
    'Distribution','binomial');

fprintf(fid, "LOGISTIC MODEL: LEARNER ~ ISI + VIOLATION\n");
fprintf(fid, "-----------------------------------------\n");
printCoefTable(fid, mdl_learner_isi_viol.Coefficients);
fprintf(fid, "\n");

p_learner_isi_viol = mdl_learner_isi_viol.Coefficients.pValue(2:end);
terms_learner_isi_viol = mdl_learner_isi_viol.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_learner_isi_viol);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_learner_isi_viol = NaN(size(p_learner_isi_viol));
p_fdr_learner_isi_viol(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: LEARNER ~ ISI + VIOLATION\n");
fprintf(fid, "-----------------------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_learner_isi_viol)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_learner_isi_viol{i}), ...
        p_learner_isi_viol(i), ...
        p_fdr_learner_isi_viol(i));
end

fprintf(fid, "\n");

fprintf(fid, "ODDS RATIOS: LEARNER ~ ISI + VIOLATION\n");
fprintf(fid, "--------------------------------------\n");

coefTbl = mdl_learner_isi_viol.Coefficients;
betaVals = coefTbl.Estimate;
seVals = coefTbl.SE;

OR = exp(betaVals);
CI_low = exp(betaVals - 1.96 * seVals);
CI_high = exp(betaVals + 1.96 * seVals);

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "OR", "CI_low", "CI_high", "pValue");

for i = 2:height(coefTbl)
    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTbl.Properties.RowNames{i}), ...
        OR(i), ...
        CI_low(i), ...
        CI_high(i), ...
        coefTbl.pValue(i));
end

fprintf(fid, "\n");

% PART B - LEARNER-ONLY GENERALIZATION
fprintf(fid, "PART B - LEARNER-ONLY GENERALIZATION\n");
fprintf(fid, "====================================\n\n");

idxL = Learner_all == 1;

Gen_L = GenMean_all(idxL);
ISI_L = ISI_cat(idxL);
Viol_L = Violation_all(idxL);

tblL = table(Participant_all(idxL), Gen_L, ISI_L, Viol_L, ...
    'VariableNames', {'ParticipantID','GenMean','ISI','Violation'});

% OLS: ISI only
mdl_gen_isi = fitlm(tblL, 'GenMean ~ ISI');

fprintf(fid, "OLS MODEL: GENMEAN ~ ISI\n");
fprintf(fid, "------------------------\n");
fprintf(fid, "R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_isi.Rsquared.Ordinary, ...
    mdl_gen_isi.Rsquared.Adjusted);

printCoefTable(fid, mdl_gen_isi.Coefficients);
fprintf(fid, "\n");

p_gen_isi = mdl_gen_isi.Coefficients.pValue(2:end);
terms_gen_isi = mdl_gen_isi.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_gen_isi);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_gen_isi = NaN(size(p_gen_isi));
p_fdr_gen_isi(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: GENMEAN ~ ISI\n");
fprintf(fid, "-----------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_gen_isi)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_gen_isi{i}), ...
        p_gen_isi(i), ...
        p_fdr_gen_isi(i));
end

fprintf(fid, "\n");

% OLS: ISI + Violation
mdl_gen_isi_viol = fitlm(tblL, 'GenMean ~ ISI + Violation');

fprintf(fid, "OLS MODEL: GENMEAN ~ ISI + VIOLATION\n");
fprintf(fid, "------------------------------------\n");
fprintf(fid, "R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_isi_viol.Rsquared.Ordinary, ...
    mdl_gen_isi_viol.Rsquared.Adjusted);

printCoefTable(fid, mdl_gen_isi_viol.Coefficients);
fprintf(fid, "\n");

p_gen_isi_viol = mdl_gen_isi_viol.Coefficients.pValue(2:end);
terms_gen_isi_viol = mdl_gen_isi_viol.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_gen_isi_viol);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_gen_isi_viol = NaN(size(p_gen_isi_viol));
p_fdr_gen_isi_viol(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: GENMEAN ~ ISI + VIOLATION\n");
fprintf(fid, "-----------------------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_gen_isi_viol)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_gen_isi_viol{i}), ...
        p_gen_isi_viol(i), ...
        p_fdr_gen_isi_viol(i));
end

fprintf(fid, "\n");

% Nested comparison
SSE_isi = mdl_gen_isi.SSE;
SSE_isi_viol = mdl_gen_isi_viol.SSE;

df_isi = mdl_gen_isi.DFE;
df_isi_viol = mdl_gen_isi_viol.DFE;

df_diff = df_isi - df_isi_viol;

F_change = ((SSE_isi - SSE_isi_viol) / df_diff) / ...
           (SSE_isi_viol / df_isi_viol);

p_change = 1 - fcdf(F_change, df_diff, df_isi_viol);

fprintf(fid, "NESTED MODEL COMPARISON: ISI ONLY vs ISI + VIOLATION\n");
fprintf(fid, "----------------------------------------------------\n");
fprintf(fid, "ISI only R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_isi.Rsquared.Ordinary, ...
    mdl_gen_isi.Rsquared.Adjusted);

fprintf(fid, "ISI + Violation R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_isi_viol.Rsquared.Ordinary, ...
    mdl_gen_isi_viol.Rsquared.Adjusted);

fprintf(fid, ...
    "F change = %.4f | df1 = %d | df2 = %d | p = %.6f\n\n", ...
    F_change, df_diff, df_isi_viol, p_change);

% Standardized violation model
zViol = (Viol_L - mean(Viol_L, "omitnan")) ./ ...
         std(Viol_L, "omitnan");

tblZ = table(Gen_L, ISI_L, zViol, ...
    'VariableNames', {'GenMean','ISI','zViolation'});

mdl_gen_isi_zviol = fitlm(tblZ, 'GenMean ~ ISI + zViolation');

fprintf(fid, "STANDARDIZED MODEL: GENMEAN ~ ISI + zVIOLATION\n");
fprintf(fid, "----------------------------------------------\n");
fprintf(fid, "R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_isi_zviol.Rsquared.Ordinary, ...
    mdl_gen_isi_zviol.Rsquared.Adjusted);

printCoefTable(fid, mdl_gen_isi_zviol.Coefficients);
fprintf(fid, "\n");

p_gen_isi_zviol = mdl_gen_isi_zviol.Coefficients.pValue(2:end);
terms_gen_isi_zviol = mdl_gen_isi_zviol.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_gen_isi_zviol);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_gen_isi_zviol = NaN(size(p_gen_isi_zviol));
p_fdr_gen_isi_zviol(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: GENMEAN ~ ISI + zVIOLATION\n");
fprintf(fid, "------------------------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_gen_isi_zviol)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_gen_isi_zviol{i}), ...
        p_gen_isi_zviol(i), ...
        p_fdr_gen_isi_zviol(i));
end

fprintf(fid, "\n");

% Interaction model
mdl_gen_interaction = fitlm(tblL, 'GenMean ~ ISI * Violation');

fprintf(fid, "INTERACTION MODEL: GENMEAN ~ ISI * VIOLATION\n");
fprintf(fid, "--------------------------------------------\n");
fprintf(fid, "R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_interaction.Rsquared.Ordinary, ...
    mdl_gen_interaction.Rsquared.Adjusted);

printCoefTable(fid, mdl_gen_interaction.Coefficients);
fprintf(fid, "\n");

p_gen_interaction = mdl_gen_interaction.Coefficients.pValue(2:end);
terms_gen_interaction = mdl_gen_interaction.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_gen_interaction);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_gen_interaction = NaN(size(p_gen_interaction));
p_fdr_gen_interaction(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: GENMEAN ~ ISI * VIOLATION\n");
fprintf(fid, "-----------------------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_gen_interaction)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_gen_interaction{i}), ...
        p_gen_interaction(i), ...
        p_fdr_gen_interaction(i));
end

fprintf(fid, "\n");

% Figure — Violation cost predicts learner state and learner strength

figOut = fullfile(resultsDir, "10_SMART_violation_predicts_learner_state_and_strength.png");

coefTableLog = mdl_learner_isi_viol.Coefficients;
coefRowsLog = coefTableLog.Properties.RowNames;
coefRowsLogNoIntercept = coefRowsLog(2:end);

idxViolLog = strcmp(coefRowsLog, 'Violation');
idxViolLogFDR = strcmp(coefRowsLogNoIntercept, 'Violation');

betaViolLog = coefTableLog.Estimate(idxViolLog);
ORViolLog = exp(betaViolLog);
pFDRViolLog = p_fdr_learner_isi_viol(idxViolLogFDR);

coefTableGen = mdl_gen_isi_viol.Coefficients;
coefRowsGen = coefTableGen.Properties.RowNames;
coefRowsGenNoIntercept = coefRowsGen(2:end);

idxViolGen = strcmp(coefRowsGen, 'Violation');
idxViolGenFDR = strcmp(coefRowsGenNoIntercept, 'Violation');

betaViolGen = coefTableGen.Estimate(idxViolGen);
pFDRViolGen = p_fdr_gen_isi_viol(idxViolGenFDR);
adjR2Gen = mdl_gen_isi_viol.Rsquared.Adjusted;

violMin = prctile(tblAll.Violation, 2.5);
violMax = prctile(tblAll.Violation, 97.5);
violGrid = linspace(violMin, violMax, 200)';

condCats = categories(tblAll.ISI);
nGrid = numel(violGrid);

predProbByCond = NaN(nGrid, numel(condCats));

for c = 1:numel(condCats)

    tmpPred = table;
    tmpPred.ISI = categorical(repmat(string(condCats{c}), nGrid, 1), condCats);
    tmpPred.Violation = violGrid;

    predProbByCond(:,c) = predict(mdl_learner_isi_viol, tmpPred);

end

predProbMean = mean(predProbByCond, 2, "omitnan");

violMinL = prctile(tblL.Violation, 2.5);
violMaxL = prctile(tblL.Violation, 97.5);
violGridL = linspace(violMinL, violMaxL, 200)';

condCatsL = categories(tblL.ISI);
predGenByCond = NaN(numel(violGridL), numel(condCatsL));

for c = 1:numel(condCatsL)

    tmpPredL = table;
    tmpPredL.ISI = categorical(repmat(string(condCatsL{c}), numel(violGridL), 1), condCatsL);
    tmpPredL.Violation = violGridL;

    predGenByCond(:,c) = predict(mdl_gen_isi_viol, tmpPredL);

end

predGenMean = mean(predGenByCond, 2, "omitnan");

figure('Position',[200 200 1200 470]);

tiledlayout(1,2, ...
    'TileSpacing','compact', ...
    'Padding','compact');

nexttile;
hold on;

rng(1);
yJitter = double(tblAll.Learner) + (rand(height(tblAll),1)-0.5)*0.08;

scatter(tblAll.Violation, yJitter, 28, ...
    'MarkerFaceColor',[0.35 0.35 0.35], ...
    'MarkerEdgeColor','none', ...
    'MarkerFaceAlpha',0.35);

plot(violGrid, predProbMean, 'k-', 'LineWidth', 2.5);

xlabel('Violation cost (ms)');
ylabel('Probability of being a learner');

title(sprintf(['Learner emergence | Learner ~ ISI + Violation\n' ...
    '\\beta = %.4f | OR = %.4f | p\\_FDR = %.4g'], ...
    betaViolLog, ORViolLog, pFDRViolLog), ...
    'Interpreter','tex');

ylim([-0.10 1.10]);
yticks([0 0.5 1]);
yticklabels({'0','0.5','1'});

grid on
box off
set(gca,'FontSize',11);

nexttile;
hold on;

scatter(tblL.Violation, tblL.GenMean, 34, ...
    'MarkerFaceColor',[0.35 0.35 0.35], ...
    'MarkerEdgeColor','none', ...
    'MarkerFaceAlpha',0.45);

plot(violGridL, predGenMean, 'k-', 'LineWidth', 2.5);

xlabel('Violation cost (ms)');
ylabel('GenMean (%)');

title(sprintf(['Learning strength among learners | GenMean ~ ISI + Violation\n' ...
    'adj. R^2 = %.3f | \\beta = %.4f | p\\_FDR = %.4g'], ...
    adjR2Gen, betaViolGen, pFDRViolGen), ...
    'Interpreter','tex');

ylim([20 100]);

grid on
box off
set(gca,'FontSize',11);

saveas(gcf, figOut);
close;

% Robust regression
mdl_gen_robust = fitlm(tblL, ...
    'GenMean ~ ISI + Violation', ...
    'RobustOpts','on');

fprintf(fid, "ROBUST REGRESSION: GENMEAN ~ ISI + VIOLATION\n");
fprintf(fid, "--------------------------------------------\n");

fprintf(fid, "R2 = %.4f | Adjusted R2 = %.4f\n", ...
    mdl_gen_robust.Rsquared.Ordinary, ...
    mdl_gen_robust.Rsquared.Adjusted);

printCoefTable(fid, mdl_gen_robust.Coefficients);
fprintf(fid, "\n");

p_gen_robust = mdl_gen_robust.Coefficients.pValue(2:end);
terms_gen_robust = mdl_gen_robust.Coefficients.Properties.RowNames(2:end);

[p_sorted, sortIdx] = sort(p_gen_robust);
m = numel(p_sorted);
p_fdr_sorted = p_sorted .* m ./ (1:m)';

for ii = m-1:-1:1
    p_fdr_sorted(ii) = min(p_fdr_sorted(ii), p_fdr_sorted(ii+1));
end

p_fdr_sorted = min(p_fdr_sorted, 1);
p_fdr_gen_robust = NaN(size(p_gen_robust));
p_fdr_gen_robust(sortIdx) = p_fdr_sorted;

fprintf(fid, "FDR-CORRECTED COEFFICIENTS: ROBUST GENMEAN ~ ISI + VIOLATION\n");
fprintf(fid, "------------------------------------------------------------\n");
fprintf(fid, "%-30s %12s %12s\n", "Term", "p", "p_FDR");

for i = 1:numel(p_gen_robust)
    fprintf(fid, "%-30s %12.6f %12.6f\n", ...
        string(terms_gen_robust{i}), ...
        p_gen_robust(i), ...
        p_fdr_gen_robust(i));
end

fprintf(fid, "\n");

% Cook's distance check
fprintf(fid, "COOK'S DISTANCE CHECK\n");
fprintf(fid, "=====================\n");

cd = mdl_gen_isi_viol.Diagnostics.CooksDistance;

threshold = 4 / numel(cd);
highCook = cd > threshold;
nHigh = sum(highCook);
maxCD = max(cd);

fprintf(fid, "Cook's D threshold: 4/n = %.4f\n", threshold);
fprintf(fid, "High-influence participants = %d\n", nHigh);
fprintf(fid, "Max Cook's D = %.4f\n\n", maxCD);

fprintf(fid, "High-influence participant list\n");
fprintf(fid, "%-20s %-10s %-12s %-12s\n", ...
    "ParticipantID", "ISI", "GenMean", "CookD");

for i = 1:height(tblL)
    if highCook(i)
        fprintf(fid, "%-20s %-10s %-12.4f %-12.4f\n", ...
            string(tblL.ParticipantID(i)), ...
            string(tblL.ISI(i)), ...
            tblL.GenMean(i), ...
            cd(i));
    end
end

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Eleventh Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as future learners:
%    - Future learner = GenMean > 25%
% 4) Compute participant-level SMART RT per block:
%    - Correct SMART trials only
%    - RT filter: 100 ms < RT < 1500 ms
%    - Blocks 1 to 6 only
% 5) Test whether future learners and non-learners diverge during SMART:
%    - Blockwise descriptive RT trajectories
%    - Mixed-effects model: RT ~ Block * Learner + ISI + (1|Participant)
% 6) Save txt output and plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");

genFile = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "11_SMART_future_learner_blockwise_divergence_results.txt");
figOut = fullfile(resultsDir, "11_SMART_future_learner_blockwise_divergence.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Load generalization data

Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category_g = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct_g = str2double(erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];
chanceLevel = 25;
nCond = numel(conditions);

% Build participant-level generalization and learner status

participantList = strings(0,1);
conditionList = strings(0,1);
genMeanList = [];
learnerList = [];

for c = 1:nCond

    cond = conditions(c);
    idxCond = SMART_g == cond;

    Pcond = unique(Participant_g(idxCond));

    for i = 1:numel(Pcond)

        pid = Pcond(i);
        idx = idxCond & Participant_g == pid;

        cat_i = Category_g(idx);
        cor_i = Correct_g(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
        multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

        genMean = mean([uni, multi], "omitnan") * 100;
        learnerFlag = genMean > chanceLevel;

        participantList(end+1,1) = pid;
        conditionList(end+1,1) = cond;
        genMeanList(end+1,1) = genMean;
        learnerList(end+1,1) = learnerFlag;

    end

end

TblLearner = table(participantList, conditionList, genMeanList, learnerList, ...
    'VariableNames', {'Participant','SMART_length','GenMean','Learner'});

% Load SMART data

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");

Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));
Block_s = str2double(erase(string(Ts.("block")), "'"));
RT_s = str2double(erase(string(Ts.("Reaction Time")), "'"));
Correct_s = str2double(erase(string(Ts.("Correct")), "'"));

% Apply SMART RT filter

idxKeep = Correct_s == 1 & ...
    RT_s > 100 & ...
    RT_s < 1500 & ...
    Block_s >= 1 & ...
    Block_s <= 6;

Participant_s = Participant_s(idxKeep);
SMART_s = SMART_s(idxKeep);
Block_s = Block_s(idxKeep);
RT_s = RT_s(idxKeep);

TblSMART = table(Participant_s, SMART_s, Block_s, RT_s, ...
    'VariableNames', {'Participant','SMART_length','Block','RT'});

% Merge SMART block data with learner status

TblSMART = outerjoin(TblSMART, TblLearner, ...
    'Keys', {'Participant','SMART_length'}, ...
    'MergeKeys', true);

TblSMART = TblSMART(~isnan(TblSMART.Learner), :);

% Compute participant-level mean RT per block

[G, pid, cond, learner, block] = findgroups( ...
    TblSMART.Participant, ...
    TblSMART.SMART_length, ...
    TblSMART.Learner, ...
    TblSMART.Block);

meanRT = splitapply(@mean, TblSMART.RT, G);
nTrials = splitapply(@numel, TblSMART.RT, G);

TblBlock = table(pid, cond, learner, block, meanRT, nTrials, ...
    'VariableNames', {'Participant','SMART_length','Learner','Block','RT','NTrials'});

% Fit mixed-effects model

TblBlock.Participant = categorical(TblBlock.Participant);
TblBlock.SMART_length = categorical(TblBlock.SMART_length, conditions);
TblBlock.Learner = categorical(TblBlock.Learner);
TblBlock.Block = double(TblBlock.Block);

mdl_divergence = fitlme(TblBlock, ...
    'RT ~ Block * Learner + SMART_length + (1|Participant)');

% Compute blockwise descriptive statistics

blocks = (1:6)';

learnerMean = NaN(numel(blocks),1);
learnerSEM = NaN(numel(blocks),1);
learnerN = NaN(numel(blocks),1);

nonLearnerMean = NaN(numel(blocks),1);
nonLearnerSEM = NaN(numel(blocks),1);
nonLearnerN = NaN(numel(blocks),1);

for b = 1:numel(blocks)

    valsLearner = TblBlock.RT(TblBlock.Block == blocks(b) & TblBlock.Learner == categorical(1));
    valsNonLearner = TblBlock.RT(TblBlock.Block == blocks(b) & TblBlock.Learner == categorical(0));

    learnerMean(b) = mean(valsLearner, "omitnan");
    learnerSEM(b) = std(valsLearner, "omitnan") / sqrt(sum(~isnan(valsLearner)));
    learnerN(b) = sum(~isnan(valsLearner));

    nonLearnerMean(b) = mean(valsNonLearner, "omitnan");
    nonLearnerSEM(b) = std(valsNonLearner, "omitnan") / sqrt(sum(~isnan(valsNonLearner)));
    nonLearnerN(b) = sum(~isnan(valsNonLearner));

end

% Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "FUTURE LEARNER BLOCKWISE DIVERGENCE RESULTS\n");
fprintf(fid, "==========================================\n\n");
fprintf(fid, "Learner definition: GenMean > 25%%\n");
fprintf(fid, "SMART RT filter: correct trials only, 100 ms < RT < 1500 ms\n");
fprintf(fid, "Blocks analyzed: 1 to 6\n\n");

fprintf(fid, "MIXED-EFFECTS MODEL\n");
fprintf(fid, "===================\n\n");
fprintf(fid, "RT ~ Block * Learner + SMART_length + (1|Participant)\n\n");

coefTable = mdl_divergence.Coefficients;

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)

    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Name{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));

end

fprintf(fid, "\nBLOCKWISE DESCRIPTIVE STATISTICS\n");
fprintf(fid, "================================\n\n");
fprintf(fid, "%-8s %-18s %-12s %-12s %-12s\n", ...
    "Block", "Group", "MeanRT", "SEM", "N");

for b = 1:numel(blocks)

    fprintf(fid, "%-8d %-18s %-12.4f %-12.4f %-12d\n", ...
        blocks(b), "Future learners", learnerMean(b), learnerSEM(b), learnerN(b));

    fprintf(fid, "%-8d %-18s %-12.4f %-12.4f %-12d\n", ...
        blocks(b), "Future non-learners", nonLearnerMean(b), nonLearnerSEM(b), nonLearnerN(b));

end

fclose(fid);

% Plot blockwise trajectories

figure('Position',[300 300 820 500]);
hold on;

errL = errorbar(blocks, learnerMean, learnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.20 0.20 0.20], ...
    'Color', [0.20 0.20 0.20]);

errNL = errorbar(blocks, nonLearnerMean, nonLearnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.70 0.70 0.70], ...
    'Color', [0.55 0.55 0.55]);

xlabel('SMART block');
ylabel('Mean RT (ms)');

title('Blockwise RT trajectories by future learner status', ...
    'Interpreter','none');

legend([errL errNL], ...
    {'Future learners','Future non-learners'}, ...
    'Location','northeast', ...
    'Box','off');

xticks(1:6);
xlim([0.75 6.25]);

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut);
close;


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Twelfth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as future learners:
%    - Future learner = GenMean > 25%
% 4) Compute participant-level SMART RT per block:
%    - Correct SMART trials only
%    - RT filter: 100 ms < RT < 1500 ms
%    - Blocks 1 to 6 only
% 5) Normalize participant RT trajectories:
%    - DeltaRT = BlockRT - Block1RT
% 6) Test whether future learners show different adaptation trajectories:
%    - Mixed-effects model:
%      DeltaRT ~ Block * Learner + SMART_length + (1|Participant)
% 7) Save txt output and plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";

resultsDir = fullfile(baseDir, "results");

genFile = fullfile(baseDir, "data", ...
    "Generalization_Data_compressed_preprocessed.xlsx");

smartFile = fullfile(baseDir, "data", ...
    "SMART_Data_compressed_preprocessed.xlsx");

txtOut = fullfile(resultsDir, ...
    "12_SMART_baseline_normalized_trajectory_results.txt");

figOut = fullfile(resultsDir, ...
    "12_SMART_baseline_normalized_trajectory.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Load generalization data

Tg = readtable(genFile, ...
    "VariableNamingRule","preserve", ...
    "TextType","string");

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));

Category_g = lower(strtrim( ...
    erase(string(Tg.("Category")), "'")));

Correct_g = str2double( ...
    erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];

chanceLevel = 25;
nCond = numel(conditions);

% Build participant-level learner table

participantList = strings(0,1);
conditionList = strings(0,1);

genMeanList = [];
learnerList = [];

for c = 1:nCond

    cond = conditions(c);

    idxCond = SMART_g == cond;

    Pcond = unique(Participant_g(idxCond));

    for i = 1:numel(Pcond)

        pid = Pcond(i);

        idx = idxCond & Participant_g == pid;

        cat_i = Category_g(idx);
        cor_i = Correct_g(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, ...
            "omitnan");

        multi = mean(cor_i(cat_i == "multi") == 1, ...
            "omitnan");

        genMean = mean([uni multi], ...
            "omitnan") * 100;

        learnerFlag = genMean > chanceLevel;

        participantList(end+1,1) = pid;
        conditionList(end+1,1) = cond;

        genMeanList(end+1,1) = genMean;
        learnerList(end+1,1) = learnerFlag;

    end

end

TblLearner = table( ...
    participantList, ...
    conditionList, ...
    genMeanList, ...
    learnerList, ...
    'VariableNames', ...
    {'Participant','SMART_length','GenMean','Learner'});

% Load SMART data

Ts = readtable(smartFile, ...
    "VariableNamingRule","preserve", ...
    "TextType","string");

Participant_s = erase( ...
    string(Ts.("Participant Private ID")), "'");

SMART_s = string(Ts.("SMART_length"));

Block_s = str2double( ...
    erase(string(Ts.block), "'"));

RT_s = str2double( ...
    erase(string(Ts.("Reaction Time")), "'"));

Correct_s = str2double( ...
    erase(string(Ts.Correct), "'"));

% Apply SMART RT filter

idxKeep = ...
    Correct_s == 1 & ...
    RT_s > 100 & ...
    RT_s < 1500 & ...
    Block_s >= 1 & ...
    Block_s <= 6;

Participant_s = Participant_s(idxKeep);
SMART_s = SMART_s(idxKeep);

Block_s = Block_s(idxKeep);
RT_s = RT_s(idxKeep);

TblSMART = table( ...
    Participant_s, ...
    SMART_s, ...
    Block_s, ...
    RT_s, ...
    'VariableNames', ...
    {'Participant','SMART_length','Block','RT'});

% Merge SMART data with learner status

TblSMART = outerjoin( ...
    TblSMART, ...
    TblLearner, ...
    'Keys', {'Participant','SMART_length'}, ...
    'MergeKeys', true);

TblSMART = TblSMART(~isnan(TblSMART.Learner), :);

% Compute participant-level block RT

[G, pid, cond, learner, block] = findgroups( ...
    TblSMART.Participant, ...
    TblSMART.SMART_length, ...
    TblSMART.Learner, ...
    TblSMART.Block);

meanRT = splitapply(@mean, TblSMART.RT, G);

TblBlock = table( ...
    pid, ...
    cond, ...
    learner, ...
    block, ...
    meanRT, ...
    'VariableNames', ...
    {'Participant','SMART_length','Learner','Block','RT'});

% Compute baseline-normalized trajectories

TblBlock.DeltaRT = NaN(height(TblBlock),1);

participants = unique(TblBlock.Participant);

for i = 1:numel(participants)

    pid_i = participants(i);

    idxP = TblBlock.Participant == pid_i;

    block1RT = TblBlock.RT( ...
        idxP & TblBlock.Block == 1);

    if isempty(block1RT)
        continue
    end

    TblBlock.DeltaRT(idxP) = ...
        TblBlock.RT(idxP) - block1RT(1);

end

% Remove missing DeltaRT rows

TblBlock = TblBlock(~isnan(TblBlock.DeltaRT), :);

% Prepare categorical variables

TblBlock.Participant = categorical(TblBlock.Participant);

TblBlock.SMART_length = categorical( ...
    TblBlock.SMART_length, ...
    conditions);

TblBlock.Learner = categorical(TblBlock.Learner);

TblBlock.Block = double(TblBlock.Block);

% Fit mixed-effects model

mdl_norm = fitlme( ...
    TblBlock, ...
    'DeltaRT ~ Block * Learner + SMART_length + (1|Participant)');

% Compute descriptive trajectories

blocks = (1:6)';

learnerMean = NaN(numel(blocks),1);
learnerSEM = NaN(numel(blocks),1);

nonLearnerMean = NaN(numel(blocks),1);
nonLearnerSEM = NaN(numel(blocks),1);

for b = 1:numel(blocks)

    valsL = TblBlock.DeltaRT( ...
        TblBlock.Block == blocks(b) & ...
        TblBlock.Learner == categorical(1));

    valsNL = TblBlock.DeltaRT( ...
        TblBlock.Block == blocks(b) & ...
        TblBlock.Learner == categorical(0));

    learnerMean(b) = mean(valsL, "omitnan");

    learnerSEM(b) = ...
        std(valsL, "omitnan") / ...
        sqrt(sum(~isnan(valsL)));

    nonLearnerMean(b) = mean(valsNL, "omitnan");

    nonLearnerSEM(b) = ...
        std(valsNL, "omitnan") / ...
        sqrt(sum(~isnan(valsNL)));

end

% Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, ...
    "BASELINE-NORMALIZED TRAJECTORY RESULTS\n");

fprintf(fid, ...
    "======================================\n\n");

fprintf(fid, ...
    "Learner definition: GenMean > 25%%\n");

fprintf(fid, ...
    "Normalization: DeltaRT = BlockRT - Block1RT\n");

fprintf(fid, ...
    "SMART RT filter: correct trials only, 100 ms < RT < 1500 ms\n");

fprintf(fid, ...
    "Blocks analyzed: 1 to 6\n\n");

fprintf(fid, ...
    "MIXED-EFFECTS MODEL\n");

fprintf(fid, ...
    "===================\n\n");

fprintf(fid, ...
    "DeltaRT ~ Block * Learner + SMART_length + (1|Participant)\n\n");

coefTable = mdl_norm.Coefficients;

fprintf(fid, ...
    "%-30s %12s %12s %12s %12s\n", ...
    "Term", ...
    "Estimate", ...
    "SE", ...
    "tStat", ...
    "pValue");

for i = 1:height(coefTable)

    fprintf(fid, ...
        "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Name{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));

end

fclose(fid);

% Plot normalized trajectories

figure('Position',[300 300 820 500]);

hold on;

errL = errorbar( ...
    blocks, ...
    learnerMean, ...
    learnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.20 0.20 0.20], ...
    'Color', [0.20 0.20 0.20]);

errNL = errorbar( ...
    blocks, ...
    nonLearnerMean, ...
    nonLearnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.70 0.70 0.70], ...
    'Color', [0.55 0.55 0.55]);

xlabel('SMART block');

ylabel('\DeltaRT from Block 1 (ms)');

title( ...
    'Baseline-normalized RT trajectories by future learner status', ...
    'Interpreter','none');

legend( ...
    [errL errNL], ...
    {'Future learners','Future non-learners'}, ...
    'Location','southwest', ...
    'Box','off');

xticks(1:6);
xlim([0.75 6.25]);

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut);
close;


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Thirteenth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as future learners:
%    - Future learner = GenMean > 25%
% 4) Compute participant-level SMART RT variability per block:
%    - Correct SMART trials only
%    - RT filter: 100 ms < RT < 1500 ms
%    - Blocks 1 to 6 only
%    - Within-block RT SD
% 5) Test whether future learners show different RT stabilization:
%    - Mixed-effects model:
%      PercentSDChange ~ Block * Learner + SMART_length + (1|Participant)
% 6) Save txt output and plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";

resultsDir = fullfile(baseDir, "results");

genFile = fullfile(baseDir, "data", ...
    "Generalization_Data_compressed_preprocessed.xlsx");

smartFile = fullfile(baseDir, "data", ...
    "SMART_Data_compressed_preprocessed.xlsx");

txtOut = fullfile(resultsDir, ...
    "13_SMART_RT_variability_trajectory_results.txt");

figOut = fullfile(resultsDir, ...
    "13_SMART_RT_variability_trajectory.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Load generalization data

Tg = readtable(genFile, ...
    "VariableNamingRule","preserve", ...
    "TextType","string");

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));

Category_g = lower(strtrim( ...
    erase(string(Tg.("Category")), "'")));

Correct_g = str2double( ...
    erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];

chanceLevel = 25;
nCond = numel(conditions);

% Build participant-level learner table

participantList = strings(0,1);
conditionList = strings(0,1);

genMeanList = [];
learnerList = [];

for c = 1:nCond

    cond = conditions(c);

    idxCond = SMART_g == cond;

    Pcond = unique(Participant_g(idxCond));

    for i = 1:numel(Pcond)

        pid = Pcond(i);

        idx = idxCond & Participant_g == pid;

        cat_i = Category_g(idx);
        cor_i = Correct_g(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, ...
            "omitnan");

        multi = mean(cor_i(cat_i == "multi") == 1, ...
            "omitnan");

        genMean = mean([uni multi], ...
            "omitnan") * 100;

        learnerFlag = genMean > chanceLevel;

        participantList(end+1,1) = pid;
        conditionList(end+1,1) = cond;

        genMeanList(end+1,1) = genMean;
        learnerList(end+1,1) = learnerFlag;

    end

end

TblLearner = table( ...
    participantList, ...
    conditionList, ...
    genMeanList, ...
    learnerList, ...
    'VariableNames', ...
    {'Participant','SMART_length','GenMean','Learner'});

% Load SMART data

Ts = readtable(smartFile, ...
    "VariableNamingRule","preserve", ...
    "TextType","string");

Participant_s = erase( ...
    string(Ts.("Participant Private ID")), "'");

SMART_s = string(Ts.("SMART_length"));

Block_s = str2double( ...
    erase(string(Ts.block), "'"));

RT_s = str2double( ...
    erase(string(Ts.("Reaction Time")), "'"));

Correct_s = str2double( ...
    erase(string(Ts.Correct), "'"));

% Apply SMART RT filter

idxKeep = ...
    Correct_s == 1 & ...
    RT_s > 100 & ...
    RT_s < 1500 & ...
    Block_s >= 1 & ...
    Block_s <= 6;

Participant_s = Participant_s(idxKeep);
SMART_s = SMART_s(idxKeep);

Block_s = Block_s(idxKeep);
RT_s = RT_s(idxKeep);

TblSMART = table( ...
    Participant_s, ...
    SMART_s, ...
    Block_s, ...
    RT_s, ...
    'VariableNames', ...
    {'Participant','SMART_length','Block','RT'});

% Merge SMART data with learner status

TblSMART = outerjoin( ...
    TblSMART, ...
    TblLearner, ...
    'Keys', {'Participant','SMART_length'}, ...
    'MergeKeys', true);

TblSMART = TblSMART(~isnan(TblSMART.Learner), :);

% Compute participant-level RT variability per block

[G, pid, cond, learner, block] = findgroups( ...
    TblSMART.Participant, ...
    TblSMART.SMART_length, ...
    TblSMART.Learner, ...
    TblSMART.Block);

RT_SD = splitapply(@std, TblSMART.RT, G);

TblVar = table( ...
    pid, ...
    cond, ...
    learner, ...
    block, ...
    RT_SD, ...
    'VariableNames', ...
    {'Participant','SMART_length','Learner','Block','RT_SD'});

% Compute baseline-normalized variability trajectories

TblVar.PercentSDChange = NaN(height(TblVar),1);

participants = unique(TblVar.Participant);

for i = 1:numel(participants)

    pid_i = participants(i);

    idxP = TblVar.Participant == pid_i;

    baselineSD = TblVar.RT_SD( ...
        idxP & TblVar.Block == 1);

    if isempty(baselineSD)
        continue
    end

    if baselineSD(1) == 0
        continue
    end

    TblVar.PercentSDChange(idxP) = ...
        100 * (TblVar.RT_SD(idxP) - baselineSD(1)) ...
        ./ baselineSD(1);

end

% Remove missing rows

TblVar = TblVar(~isnan(TblVar.PercentSDChange), :);

% Prepare categorical variables

TblVar.Participant = categorical(TblVar.Participant);

TblVar.SMART_length = categorical( ...
    TblVar.SMART_length, ...
    conditions);

TblVar.Learner = categorical(TblVar.Learner);

TblVar.Block = double(TblVar.Block);

% Fit mixed-effects model

mdl_var = fitlme( ...
    TblVar, ...
    'PercentSDChange ~ Block * Learner + SMART_length + (1|Participant)');

% Compute descriptive trajectories

blocks = (1:6)';

learnerMean = NaN(numel(blocks),1);
learnerSEM = NaN(numel(blocks),1);

nonLearnerMean = NaN(numel(blocks),1);
nonLearnerSEM = NaN(numel(blocks),1);

for b = 1:numel(blocks)

    valsL = TblVar.PercentSDChange( ...
        TblVar.Block == blocks(b) & ...
        TblVar.Learner == categorical(1));
    
    valsNL = TblVar.PercentSDChange( ...
        TblVar.Block == blocks(b) & ...
        TblVar.Learner == categorical(0));

    learnerMean(b) = mean(valsL, "omitnan");

    learnerSEM(b) = ...
        std(valsL, "omitnan") / ...
        sqrt(sum(~isnan(valsL)));

    nonLearnerMean(b) = mean(valsNL, "omitnan");

    nonLearnerSEM(b) = ...
        std(valsNL, "omitnan") / ...
        sqrt(sum(~isnan(valsNL)));

end

% Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, ...
    "RT VARIABILITY TRAJECTORY RESULTS\n");

fprintf(fid, ...
    "=================================\n\n");

fprintf(fid, ...
    "Learner definition: GenMean > 25%%\n");

fprintf(fid, ...
    "SMART RT filter: correct trials only, 100 ms < RT < 1500 ms\n");

fprintf(fid, ...
    "Blocks analyzed: 1 to 6\n");

fprintf(fid, ...
    "Within-block metric: Percent SD change relative to Block 1\n\n");

fprintf(fid, ...
    "MIXED-EFFECTS MODEL\n");

fprintf(fid, ...
    "===================\n\n");

fprintf(fid, ...
    "PercentSDChange ~ Block * Learner + SMART_length + (1|Participant)\n\n");

coefTable = mdl_var.Coefficients;

fprintf(fid, ...
    "%-30s %12s %12s %12s %12s\n", ...
    "Term", ...
    "Estimate", ...
    "SE", ...
    "tStat", ...
    "pValue");

for i = 1:height(coefTable)

    fprintf(fid, ...
        "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Name{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));

end

fclose(fid);

% Plot RT variability trajectories

figure('Position',[300 300 820 500]);

hold on;

errL = errorbar( ...
    blocks, ...
    learnerMean, ...
    learnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.20 0.20 0.20], ...
    'Color', [0.20 0.20 0.20]);

errNL = errorbar( ...
    blocks, ...
    nonLearnerMean, ...
    nonLearnerSEM, ...
    '-o', ...
    'LineWidth', 2.5, ...
    'MarkerSize', 7, ...
    'MarkerFaceColor', [0.70 0.70 0.70], ...
    'Color', [0.55 0.55 0.55]);

xlabel('SMART block');

ylabel('% SD change from Block 1');

title('RT variability stabilization by future learner status', ...
    'Interpreter','none');

legend( ...
    [errL errNL], ...
    {'Future learners','Future non-learners'}, ...
    'Location','northeast', ...
    'Box','off');

xticks(1:6);
xlim([0.75 6.25]);

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut);
close;


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Fourteenth Part
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as future learners:
%    - Future learner = GenMean > 25%
% 4) Compute trial-to-trial RT autocorrelation:
%    - Correct SMART trials only
%    - RT filter: 100 ms < RT < 1500 ms
%    - Blocks 1 to 6 only
%    - RTs z-scored within participant and block before autocorrelation
%    - Lag-1 autocorrelation computed across normalized SMART sequence
% 5) Test whether future learners show stronger temporal RT structure:
%    - Linear model: RT_Autocorr_Z ~ Learner + SMART_length
% 6) Save txt output and plot
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
resultsDir = fullfile(baseDir, "results");

genFile = fullfile(baseDir, "data", "Generalization_Data_compressed_preprocessed.xlsx");
smartFile = fullfile(baseDir, "data", "SMART_Data_compressed_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "14_SMART_zscored_RT_autocorrelation_results.txt");
figOut = fullfile(resultsDir, "14_SMART_zscored_RT_autocorrelation.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Load generalization data

Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category_g = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct_g = str2double(erase(string(Tg.("Correct")), "'"));

conditions = ["ms0","ms250","ms500","ms1100"];
chanceLevel = 25;
nCond = numel(conditions);

% Build participant-level learner table

participantList = strings(0,1);
conditionList = strings(0,1);
genMeanList = [];
learnerList = [];

for c = 1:nCond

    cond = conditions(c);
    idxCond = SMART_g == cond;

    Pcond = unique(Participant_g(idxCond));

    for i = 1:numel(Pcond)

        pid = Pcond(i);
        idx = idxCond & Participant_g == pid;

        cat_i = Category_g(idx);
        cor_i = Correct_g(idx);

        uni = mean(cor_i(cat_i == "uni") == 1, "omitnan");
        multi = mean(cor_i(cat_i == "multi") == 1, "omitnan");

        genMean = mean([uni, multi], "omitnan") * 100;
        learnerFlag = genMean > chanceLevel;

        participantList(end+1,1) = pid;
        conditionList(end+1,1) = cond;
        genMeanList(end+1,1) = genMean;
        learnerList(end+1,1) = learnerFlag;

    end

end

TblLearner = table(participantList, conditionList, genMeanList, learnerList, ...
    'VariableNames', {'Participant','SMART_length','GenMean','Learner'});

% Load SMART data

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");

Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));
Block_s = str2double(erase(string(Ts.("block")), "'"));
RT_s = str2double(erase(string(Ts.("Reaction Time")), "'"));
Correct_s = str2double(erase(string(Ts.("Correct")), "'"));

TrialIndex = (1:height(Ts))';

% Apply SMART RT filter

idxKeep = Correct_s == 1 & ...
    RT_s > 100 & ...
    RT_s < 1500 & ...
    Block_s >= 1 & ...
    Block_s <= 6;

Participant_s = Participant_s(idxKeep);
SMART_s = SMART_s(idxKeep);
Block_s = Block_s(idxKeep);
RT_s = RT_s(idxKeep);
TrialIndex = TrialIndex(idxKeep);

TblSMART = table(Participant_s, SMART_s, Block_s, RT_s, TrialIndex, ...
    'VariableNames', {'Participant','SMART_length','Block','RT','TrialIndex'});

% Merge SMART data with learner status

TblSMART = outerjoin(TblSMART, TblLearner, ...
    'Keys', {'Participant','SMART_length'}, ...
    'MergeKeys', true);

TblSMART = TblSMART(~isnan(TblSMART.Learner), :);

% Sort trials within participant

TblSMART = sortrows(TblSMART, {'Participant','SMART_length','TrialIndex'});

% Z-score RT within participant and block

TblSMART.RT_Z = NaN(height(TblSMART),1);

participants = unique(TblSMART.Participant);

for i = 1:numel(participants)

    pid = participants(i);
    idxP = TblSMART.Participant == pid;

    blocks_i = unique(TblSMART.Block(idxP));

    for b = 1:numel(blocks_i)

        block_i = blocks_i(b);
        idxPB = idxP & TblSMART.Block == block_i;

        rtBlock = TblSMART.RT(idxPB);

        muRT = mean(rtBlock, "omitnan");
        sdRT = std(rtBlock, "omitnan");

        if isnan(sdRT) || sdRT == 0
            continue
        end

        TblSMART.RT_Z(idxPB) = (rtBlock - muRT) ./ sdRT;

    end

end

TblSMART = TblSMART(~isnan(TblSMART.RT_Z), :);

% Compute participant-level lag-1 autocorrelation on z-scored RT

participants = unique(TblSMART.Participant);

autoParticipant = strings(0,1);
autoCondition = strings(0,1);
autoLearner = [];
autoValue = [];
autoNTrials = [];

for i = 1:numel(participants)

    pid = participants(i);
    idxP = TblSMART.Participant == pid;

    RTz_i = TblSMART.RT_Z(idxP);

    if numel(RTz_i) < 10
        continue
    end

    r = corr(RTz_i(1:end-1), RTz_i(2:end), 'Rows','complete');

    if isnan(r)
        continue
    end

    autoParticipant(end+1,1) = pid;
    autoCondition(end+1,1) = TblSMART.SMART_length(find(idxP,1));
    autoLearner(end+1,1) = TblSMART.Learner(find(idxP,1));
    autoValue(end+1,1) = r;
    autoNTrials(end+1,1) = numel(RTz_i);

end

TblAuto = table(autoParticipant, autoCondition, autoLearner, autoValue, autoNTrials, ...
    'VariableNames', {'Participant','SMART_length','Learner','RT_Autocorr_Z','NTrials'});

% Prepare variables for model

TblAuto.SMART_length = categorical(TblAuto.SMART_length, conditions);
TblAuto.Learner = categorical(TblAuto.Learner);

% Fit linear model

mdl_auto = fitlm(TblAuto, 'RT_Autocorr_Z ~ Learner + SMART_length');

% Compute descriptive statistics

valsL = TblAuto.RT_Autocorr_Z(TblAuto.Learner == categorical(1));
valsNL = TblAuto.RT_Autocorr_Z(TblAuto.Learner == categorical(0));

meanL = mean(valsL, "omitnan");
meanNL = mean(valsNL, "omitnan");

semL = std(valsL, "omitnan") / sqrt(sum(~isnan(valsL)));
semNL = std(valsNL, "omitnan") / sqrt(sum(~isnan(valsNL)));

nL = sum(~isnan(valsL));
nNL = sum(~isnan(valsNL));

% Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "Z-SCORED RT AUTOCORRELATION RESULTS\n");
fprintf(fid, "===================================\n\n");
fprintf(fid, "Learner definition: GenMean > 25%%\n");
fprintf(fid, "SMART RT filter: correct trials only, 100 ms < RT < 1500 ms\n");
fprintf(fid, "Blocks analyzed: 1 to 6\n");
fprintf(fid, "Metric: lag-1 RT autocorrelation\n");
fprintf(fid, "Normalization: RT z-scored within participant and block before autocorrelation\n\n");

fprintf(fid, "MODEL\n");
fprintf(fid, "=====\n\n");
fprintf(fid, "RT_Autocorr_Z ~ Learner + SMART_length\n\n");

coefTable = mdl_auto.Coefficients;

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)

    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Properties.RowNames{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));

end

fprintf(fid, "\nDESCRIPTIVE STATISTICS\n");
fprintf(fid, "======================\n\n");
fprintf(fid, "Future learners:     mean = %.4f | SEM = %.4f | n = %d\n", meanL, semL, nL);
fprintf(fid, "Future non-learners: mean = %.4f | SEM = %.4f | n = %d\n", meanNL, semNL, nNL);

fclose(fid);

% Plot autocorrelation distributions

figure('Position',[300 300 620 450]);
hold on;

rng(1);

xL = ones(size(valsL)) + (rand(size(valsL)) - 0.5) * 0.18;
xNL = 2 * ones(size(valsNL)) + (rand(size(valsNL)) - 0.5) * 0.18;

scatter(xL, valsL, 45, ...
    'filled', ...
    'MarkerFaceColor', [0.20 0.20 0.20], ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', 'none');

scatter(xNL, valsNL, 45, ...
    'filled', ...
    'MarkerFaceColor', [0.65 0.65 0.65], ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', 'none');

errorbar(1, meanL, semL, ...
    'kd', ...
    'MarkerSize', 10, ...
    'MarkerFaceColor', 'k', ...
    'LineWidth', 1.8);

errorbar(2, meanNL, semNL, ...
    'kd', ...
    'MarkerSize', 10, ...
    'MarkerFaceColor', 'k', ...
    'LineWidth', 1.8);

yline(0, '--k', ...
    'LineWidth', 1.2, ...
    'Alpha', 0.35);

xlim([0.5 2.5]);

xticks([1 2]);
xticklabels({'Future learners','Future non-learners'});

ylabel('Lag-1 autocorrelation of z-scored RT');

title('Trial-to-trial RT structure by future learner status', ...
    'Interpreter','none');

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut);
close;

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Part 15.1
% 1) Load preprocessed SMART and Generalization datasets
% 2) Build participant-level GenMean:
%    - UNI accuracy
%    - MULTI accuracy
%    - GenMean = mean(UNI accuracy, MULTI accuracy)
% 3) Classify participants as future learners:
%    - Future learner = GenMean > 25%
% 4) Merge learner status into preprocessed SMART data
% 5) Keep Blocks 1 to 6 only
% 6) Build trial-level category transition variables:
%    - Previous category_type
%    - Current category_type
%    - Transition type: uni->uni, uni->multi, multi->uni, multi->multi
%    - Repeat/switch status
% 7) Normalize RT:
%    - RT z-scored within participant and block
% 8) Save transition-ready table
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
dataDir = fullfile(baseDir, "data");
resultsDir = fullfile(baseDir, "results");

smartFile = fullfile(dataDir, "SMART_Data_compressed_preprocessed.xlsx");
genFile = fullfile(dataDir, "Generalization_Data_compressed_preprocessed.xlsx");

transitionOut = fullfile(dataDir, "SMART_Category_Transitions_preprocessed.xlsx");
txtOut = fullfile(resultsDir, "15_1_SMART_category_transition_table_report.txt");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Step 1 — Load data

Ts = readtable(smartFile, "VariableNamingRule","preserve", "TextType","string");
Tg = readtable(genFile, "VariableNamingRule","preserve", "TextType","string");

conditions = ["ms0","ms250","ms500","ms1100"];
chanceLevel = 25;

% Step 2 — Build learner table from generalization data

Participant_g = erase(string(Tg.("Participant Private ID")), "'");
SMART_g = string(Tg.("SMART_length"));
Category_g = lower(strtrim(erase(string(Tg.("Category")), "'")));
Correct_g = str2double(erase(string(Tg.("Correct")), "'"));

participantList = strings(0,1);
conditionList = strings(0,1);
genUniList = [];
genMultiList = [];
genMeanList = [];
learnerList = [];

for c = 1:numel(conditions)

    cond = conditions(c);
    idxCond = SMART_g == cond;

    Pcond = unique(Participant_g(idxCond));

    for i = 1:numel(Pcond)

        pid = Pcond(i);
        idx = idxCond & Participant_g == pid;

        cat_i = Category_g(idx);
        cor_i = Correct_g(idx);

        genUni = mean(cor_i(cat_i == "uni") == 1, "omitnan") * 100;
        genMulti = mean(cor_i(cat_i == "multi") == 1, "omitnan") * 100;
        genMean = mean([genUni, genMulti], "omitnan");

        learnerFlag = genMean > chanceLevel;

        participantList(end+1,1) = pid;
        conditionList(end+1,1) = cond;
        genUniList(end+1,1) = genUni;
        genMultiList(end+1,1) = genMulti;
        genMeanList(end+1,1) = genMean;
        learnerList(end+1,1) = learnerFlag;

    end

end

TblLearner = table(participantList, conditionList, genUniList, genMultiList, genMeanList, learnerList, ...
    'VariableNames', {'Participant','SMART_length','GenUNI','GenMULTI','GenMean','Learner'});

% Step 3 — Prepare SMART table

Participant_s = erase(string(Ts.("Participant Private ID")), "'");
SMART_s = string(Ts.("SMART_length"));
RT_s = str2double(erase(string(Ts.("Reaction Time")), "'"));
Response_s = str2double(erase(string(Ts.("Response")), "'"));
CorrectAnswer_s = str2double(erase(string(Ts.("Correct Answer")), "'"));
CategoryType_s = lower(strtrim(erase(string(Ts.("category_type")), "'")));
Block_s = str2double(erase(string(Ts.("block")), "'"));

TrialIndex = (1:height(Ts))';

TblSMART = table(Participant_s, SMART_s, RT_s, Response_s, CorrectAnswer_s, CategoryType_s, Block_s, TrialIndex, ...
    'VariableNames', {'Participant','SMART_length','RT','Response','CorrectAnswer','CategoryType','Block','TrialIndex'});

% Step 4 — Keep Blocks 1 to 6 and valid category_type rows

idxKeep = TblSMART.Block >= 1 & ...
    TblSMART.Block <= 6 & ...
    (TblSMART.CategoryType == "uni" | TblSMART.CategoryType == "multi");

TblSMART = TblSMART(idxKeep, :);

% Step 5 — Merge SMART table with learner status

TblSMART = outerjoin(TblSMART, TblLearner, ...
    'Keys', {'Participant','SMART_length'}, ...
    'MergeKeys', true);

TblSMART = TblSMART(~isnan(TblSMART.Learner), :);

% Step 6 — Preserve original SMART row order

TblSMART = sortrows(TblSMART, 'TrialIndex');

% Step 7 — Z-score RT within participant and block

TblSMART.RT_Z = NaN(height(TblSMART),1);

participants = unique(TblSMART.Participant);

for i = 1:numel(participants)

    pid = participants(i);
    idxP = TblSMART.Participant == pid;

    blocks_i = unique(TblSMART.Block(idxP));

    for b = 1:numel(blocks_i)

        block_i = blocks_i(b);
        idxPB = idxP & TblSMART.Block == block_i;

        rtBlock = TblSMART.RT(idxPB);

        muRT = mean(rtBlock, "omitnan");
        sdRT = std(rtBlock, "omitnan");

        if isnan(sdRT) || sdRT == 0
            continue
        end

        TblSMART.RT_Z(idxPB) = (rtBlock - muRT) ./ sdRT;

    end

end

TblSMART = TblSMART(~isnan(TblSMART.RT_Z), :);

% Step 8 — Build category transition variables within participant and block

TblSMART.PrevCategoryType = strings(height(TblSMART),1);
TblSMART.TransitionType = strings(height(TblSMART),1);
TblSMART.RepeatSwitch = strings(height(TblSMART),1);

participants = unique(TblSMART.Participant);

for i = 1:numel(participants)

    pid = participants(i);
    idxP = TblSMART.Participant == pid;

    blocks_i = unique(TblSMART.Block(idxP));

    for b = 1:numel(blocks_i)

        block_i = blocks_i(b);
        idxPB = find(idxP & TblSMART.Block == block_i);

        if numel(idxPB) < 2
            continue
        end

        catSeq = TblSMART.CategoryType(idxPB);

        for t = 2:numel(idxPB)

            rowIdx = idxPB(t);

            prevCat = catSeq(t-1);
            currCat = catSeq(t);

            TblSMART.PrevCategoryType(rowIdx) = prevCat;
            TblSMART.TransitionType(rowIdx) = prevCat + "->" + currCat;

            if prevCat == currCat
                TblSMART.RepeatSwitch(rowIdx) = "repeat";
            else
                TblSMART.RepeatSwitch(rowIdx) = "switch";
            end

        end

    end

end

TblTrans = TblSMART(TblSMART.TransitionType ~= "", :);

% Step 9 — Save transition-ready table

writetable(TblTrans, transitionOut);

% Step 10 — Save report

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "SMART CATEGORY TRANSITION TABLE REPORT\n");
fprintf(fid, "======================================\n\n");
fprintf(fid, "Input SMART file: %s\n", smartFile);
fprintf(fid, "Input Generalization file: %s\n", genFile);
fprintf(fid, "Output transition table: %s\n\n", transitionOut);

fprintf(fid, "Learner definition: GenMean > 25%%\n");
fprintf(fid, "SMART data source: preprocessed SMART file from Part 0\n");
fprintf(fid, "No additional RT or correctness filtering applied in Part 15.1\n");
fprintf(fid, "Blocks retained: 1 to 6\n");
fprintf(fid, "RT normalization: z-scored within participant and block\n");
fprintf(fid, "Transition definition: previous category_type -> current category_type within same participant and block\n\n");

fprintf(fid, "SUMMARY\n");
fprintf(fid, "=======\n");
fprintf(fid, "Rows in preprocessed SMART file: %d\n", height(Ts));
fprintf(fid, "Rows after Blocks 1-6/category filter: %d\n", height(TblSMART));
fprintf(fid, "Rows with valid transition labels: %d\n", height(TblTrans));
fprintf(fid, "Participants retained: %d\n\n", numel(unique(TblTrans.Participant)));

fprintf(fid, "TRANSITION COUNTS\n");
fprintf(fid, "=================\n");

transitionOrder = ["uni->uni","uni->multi","multi->uni","multi->multi"];

for i = 1:numel(transitionOrder)

    n = sum(TblTrans.TransitionType == transitionOrder(i));
    fprintf(fid, "%-12s %d\n", transitionOrder(i), n);

end

fprintf(fid, "\nREPEAT/SWITCH COUNTS\n");
fprintf(fid, "====================\n");
fprintf(fid, "repeat      %d\n", sum(TblTrans.RepeatSwitch == "repeat"));
fprintf(fid, "switch      %d\n", sum(TblTrans.RepeatSwitch == "switch"));

fprintf(fid, "\nLEARNER COUNTS\n");
fprintf(fid, "==============\n");

learnerParticipants = unique(TblTrans.Participant(TblTrans.Learner == 1));
nonLearnerParticipants = unique(TblTrans.Participant(TblTrans.Learner == 0));

fprintf(fid, "Future learners: %d\n", numel(learnerParticipants));
fprintf(fid, "Future non-learners: %d\n", numel(nonLearnerParticipants));

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Part 15.2
% 1) Load transition-ready SMART table from Part 15.1
% 2) Test full category-transition sensitivity:
%    - RT_Z ~ Block * Learner * TransitionType + SMART_length + (1|Participant)
% 3) Test simplified repeat/switch sensitivity:
%    - RT_Z ~ Block * Learner * RepeatSwitch + SMART_length + (1|Participant)
% 4) Compute descriptive statistics:
%    - RT_Z by TransitionType and Learner
%    - RT_Z by RepeatSwitch and Learner
% 5) Save txt output and plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
dataDir = fullfile(baseDir, "data");
resultsDir = fullfile(baseDir, "results");

transitionFile = fullfile(dataDir, "SMART_Category_Transitions_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "15_2_SMART_category_transition_sensitivity_results.txt");
figOut1 = fullfile(resultsDir, "15_2_SMART_transition_type_RTz.png");
figOut2 = fullfile(resultsDir, "15_2_SMART_repeat_switch_RTz.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Step 1 — Load transition-ready data

T = readtable(transitionFile, "VariableNamingRule","preserve", "TextType","string");

% Step 2 — Prepare variables

conditions = ["ms0","ms250","ms500","ms1100"];
transitionOrder = ["uni->uni","uni->multi","multi->uni","multi->multi"];
repeatOrder = ["repeat","switch"];

T.RT_Z = str2double(string(T.RT_Z));
T.Block = str2double(string(T.Block));
T.Learner = str2double(string(T.Learner));

T.Participant = categorical(string(T.Participant));
T.SMART_length = categorical(string(T.SMART_length), conditions);
T.Learner = categorical(T.Learner);
T.TransitionType = categorical(string(T.TransitionType), transitionOrder);
T.RepeatSwitch = categorical(string(T.RepeatSwitch), repeatOrder);

T = T(~isnan(T.RT_Z), :);

% Step 3 — Fit mixed-effects models

mdl_transition = fitlme(T, ...
    'RT_Z ~ Block * Learner * TransitionType + SMART_length + (1|Participant)');

mdl_repeat = fitlme(T, ...
    'RT_Z ~ Block * Learner * RepeatSwitch + SMART_length + (1|Participant)');

% Step 4 — Compute descriptive statistics by transition type and learner

[G1, transGroup, learnerGroup] = findgroups(T.TransitionType, T.Learner);

meanRTz_transition = splitapply(@mean, T.RT_Z, G1);
semRTz_transition = splitapply(@(x) std(x,"omitnan") ./ sqrt(sum(~isnan(x))), T.RT_Z, G1);
n_transition = splitapply(@(x) sum(~isnan(x)), T.RT_Z, G1);

TblTransitionDesc = table(transGroup, learnerGroup, meanRTz_transition, semRTz_transition, n_transition, ...
    'VariableNames', {'TransitionType','Learner','MeanRT_Z','SEM','N'});

% Step 5 — Compute descriptive statistics by repeat/switch and learner

[G2, repeatGroup, learnerGroup2] = findgroups(T.RepeatSwitch, T.Learner);

meanRTz_repeat = splitapply(@mean, T.RT_Z, G2);
semRTz_repeat = splitapply(@(x) std(x,"omitnan") ./ sqrt(sum(~isnan(x))), T.RT_Z, G2);
n_repeat = splitapply(@(x) sum(~isnan(x)), T.RT_Z, G2);

TblRepeatDesc = table(repeatGroup, learnerGroup2, meanRTz_repeat, semRTz_repeat, n_repeat, ...
    'VariableNames', {'RepeatSwitch','Learner','MeanRT_Z','SEM','N'});

% Step 6 — Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "CATEGORY TRANSITION SENSITIVITY RESULTS\n");
fprintf(fid, "=======================================\n\n");

fprintf(fid, "Input file: %s\n\n", transitionFile);
fprintf(fid, "RT variable: RT_Z\n");
fprintf(fid, "Normalization: RT z-scored within participant and block in Part 15.1\n");
fprintf(fid, "Blocks analyzed: 1 to 6\n");
fprintf(fid, "Transition definition: previous category_type -> current category_type within same participant and block\n\n");

fprintf(fid, "MODEL 1 - FULL CATEGORY TRANSITION MODEL\n");
fprintf(fid, "========================================\n\n");
fprintf(fid, "RT_Z ~ Block * Learner * TransitionType + SMART_length + (1|Participant)\n\n");

coefTable = mdl_transition.Coefficients;

fprintf(fid, "%-50s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)

    fprintf(fid, "%-50s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Name{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));

end

fprintf(fid, "\nMODEL 2 - REPEAT/SWITCH MODEL\n");
fprintf(fid, "=============================\n\n");
fprintf(fid, "RT_Z ~ Block * Learner * RepeatSwitch + SMART_length + (1|Participant)\n\n");

coefTable2 = mdl_repeat.Coefficients;

fprintf(fid, "%-50s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable2)

    fprintf(fid, "%-50s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable2.Name{i}), ...
        coefTable2.Estimate(i), ...
        coefTable2.SE(i), ...
        coefTable2.tStat(i), ...
        coefTable2.pValue(i));

end

fprintf(fid, "\nDESCRIPTIVE STATISTICS - TRANSITION TYPE\n");
fprintf(fid, "========================================\n\n");

fprintf(fid, "%-18s %-12s %12s %12s %12s\n", ...
    "TransitionType", "Learner", "MeanRT_Z", "SEM", "N");

for i = 1:height(TblTransitionDesc)

    fprintf(fid, "%-18s %-12s %12.4f %12.4f %12d\n", ...
        string(TblTransitionDesc.TransitionType(i)), ...
        string(TblTransitionDesc.Learner(i)), ...
        TblTransitionDesc.MeanRT_Z(i), ...
        TblTransitionDesc.SEM(i), ...
        TblTransitionDesc.N(i));

end

fprintf(fid, "\nDESCRIPTIVE STATISTICS - REPEAT/SWITCH\n");
fprintf(fid, "======================================\n\n");

fprintf(fid, "%-18s %-12s %12s %12s %12s\n", ...
    "RepeatSwitch", "Learner", "MeanRT_Z", "SEM", "N");

for i = 1:height(TblRepeatDesc)

    fprintf(fid, "%-18s %-12s %12.4f %12.4f %12d\n", ...
        string(TblRepeatDesc.RepeatSwitch(i)), ...
        string(TblRepeatDesc.Learner(i)), ...
        TblRepeatDesc.MeanRT_Z(i), ...
        TblRepeatDesc.SEM(i), ...
        TblRepeatDesc.N(i));

end

fclose(fid);

% Step 7 — Plot full transition-type means

figure('Position',[300 300 820 460]);
hold on;

x = 1:numel(transitionOrder);
barWidth = 0.34;

learnerVals = NaN(numel(transitionOrder),1);
nonLearnerVals = NaN(numel(transitionOrder),1);
learnerSEM = NaN(numel(transitionOrder),1);
nonLearnerSEM = NaN(numel(transitionOrder),1);

for i = 1:numel(transitionOrder)

    idxL = TblTransitionDesc.TransitionType == categorical(transitionOrder(i), transitionOrder) & ...
        TblTransitionDesc.Learner == categorical(1);

    idxNL = TblTransitionDesc.TransitionType == categorical(transitionOrder(i), transitionOrder) & ...
        TblTransitionDesc.Learner == categorical(0);

    learnerVals(i) = TblTransitionDesc.MeanRT_Z(idxL);
    nonLearnerVals(i) = TblTransitionDesc.MeanRT_Z(idxNL);

    learnerSEM(i) = TblTransitionDesc.SEM(idxL);
    nonLearnerSEM(i) = TblTransitionDesc.SEM(idxNL);

end

b1 = bar(x - barWidth/2, learnerVals, barWidth, ...
    'FaceColor', [0.20 0.20 0.20], ...
    'EdgeColor', 'none');

b2 = bar(x + barWidth/2, nonLearnerVals, barWidth, ...
    'FaceColor', [0.65 0.65 0.65], ...
    'EdgeColor', 'none');

errorbar(x - barWidth/2, learnerVals, learnerSEM, ...
    'k.', 'LineWidth', 1.3);

errorbar(x + barWidth/2, nonLearnerVals, nonLearnerSEM, ...
    'k.', 'LineWidth', 1.3);

yline(0, '--k', 'LineWidth', 1.2, 'Alpha', 0.35);

xticks(x);
xticklabels(transitionOrder);
xtickangle(25);

ylabel('RT z-score');
title('Category-transition RT sensitivity by future learner status', ...
    'Interpreter','none');

legend([b1 b2], ...
    {'Future learners','Future non-learners'}, ...
    'Location','northoutside', ...
    'Orientation','horizontal', ...
    'Box','off');

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut1);
close;

% Step 8 — Plot repeat/switch means

figure('Position',[300 300 650 450]);
hold on;

x = 1:numel(repeatOrder);
barWidth = 0.34;

learnerVals = NaN(numel(repeatOrder),1);
nonLearnerVals = NaN(numel(repeatOrder),1);
learnerSEM = NaN(numel(repeatOrder),1);
nonLearnerSEM = NaN(numel(repeatOrder),1);

for i = 1:numel(repeatOrder)

    idxL = TblRepeatDesc.RepeatSwitch == categorical(repeatOrder(i), repeatOrder) & ...
        TblRepeatDesc.Learner == categorical(1);

    idxNL = TblRepeatDesc.RepeatSwitch == categorical(repeatOrder(i), repeatOrder) & ...
        TblRepeatDesc.Learner == categorical(0);

    learnerVals(i) = TblRepeatDesc.MeanRT_Z(idxL);
    nonLearnerVals(i) = TblRepeatDesc.MeanRT_Z(idxNL);

    learnerSEM(i) = TblRepeatDesc.SEM(idxL);
    nonLearnerSEM(i) = TblRepeatDesc.SEM(idxNL);

end

b1 = bar(x - barWidth/2, learnerVals, barWidth, ...
    'FaceColor', [0.20 0.20 0.20], ...
    'EdgeColor', 'none');

b2 = bar(x + barWidth/2, nonLearnerVals, barWidth, ...
    'FaceColor', [0.65 0.65 0.65], ...
    'EdgeColor', 'none');

errorbar(x - barWidth/2, learnerVals, learnerSEM, ...
    'k.', 'LineWidth', 1.3);

errorbar(x + barWidth/2, nonLearnerVals, nonLearnerSEM, ...
    'k.', 'LineWidth', 1.3);

yline(0, '--k', 'LineWidth', 1.2, 'Alpha', 0.35);

xticks(x);
xticklabels(repeatOrder);

ylabel('RT z-score');
title('Repeat/switch RT sensitivity by future learner status', ...
    'Interpreter','none');

legend([b1 b2], ...
    {'Future learners','Future non-learners'}, ...
    'Location','northoutside', ...
    'Orientation','horizontal', ...
    'Box','off');

grid on
box off

ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut2);
close;

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Part 16
% 1) Load transition-ready SMART table from Part 15.1
% 2) Visualize category-transition RT sensitivity separately by ISI:
%    - ms0
%    - ms250
%    - ms500
%    - ms1100
% 3) Compare:
%    - Future learners
%    - Future non-learners
% 4) Descriptive visualization only:
%    - No high-order interaction models
% 5) Create:
%    - Full transition-type plots
%    - Repeat/switch plots
% 6) Save descriptive summaries and figures
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
dataDir = fullfile(baseDir, "data");
resultsDir = fullfile(baseDir, "results");

transitionFile = fullfile(dataDir, "SMART_Category_Transitions_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "16_SMART_transition_sensitivity_by_ISI.txt");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Step 1 — Load transition-ready table

T = readtable(transitionFile, ...
    "VariableNamingRule","preserve", ...
    "TextType","string");

conditions = ["ms0","ms250","ms500","ms1100"];
transitionOrder = ["uni->uni","uni->multi","multi->uni","multi->multi"];
repeatOrder = ["repeat","switch"];

condColors = containers.Map('KeyType','char','ValueType','any');

condColors('ms0') = [
    0.85 0.33 0.10
    0.45 0.15 0.05
];

condColors('ms250') = [
    0.10 0.35 0.85
    0.05 0.15 0.45
];

condColors('ms500') = [
    0.10 0.65 0.20
    0.05 0.35 0.10
];

condColors('ms1100') = [
    0.85 0.10 0.10
    0.45 0.05 0.05
];

% Step 2 — Prepare variables

T.RT_Z = str2double(string(T.RT_Z));
T.Block = str2double(string(T.Block));
T.Learner = str2double(string(T.Learner));

T = T(~isnan(T.RT_Z), :);

% Step 3 — Open txt report

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file.");
end

fprintf(fid, "CATEGORY TRANSITION SENSITIVITY BY ISI\n");
fprintf(fid, "======================================\n\n");

fprintf(fid, "Input file: %s\n\n", transitionFile);

% Step 4 — Loop across ISI conditions

for c = 1:numel(conditions)

    cond = conditions(c);

    idxCond = string(T.SMART_length) == cond;

    Tc = T(idxCond,:);

    fprintf(fid, "CONDITION: %s\n", cond);
    fprintf(fid, "===============================\n\n");

    % ------------------------------------------------------------
    % Transition-type descriptive statistics
    % ------------------------------------------------------------

    [G1, transGroup, learnerGroup] = ...
        findgroups(string(Tc.TransitionType), Tc.Learner);

    meanRTz = splitapply(@mean, Tc.RT_Z, G1);
    semRTz = splitapply(@(x) std(x,"omitnan") ./ sqrt(sum(~isnan(x))), Tc.RT_Z, G1);
    nRTz = splitapply(@(x) sum(~isnan(x)), Tc.RT_Z, G1);

    TblDesc = table(transGroup, learnerGroup, meanRTz, semRTz, nRTz, ...
        'VariableNames', ...
        {'TransitionType','Learner','MeanRT_Z','SEM','N'});

    fprintf(fid, "TRANSITION-TYPE DESCRIPTIVE STATISTICS\n");
    fprintf(fid, "--------------------------------------\n\n");

    fprintf(fid, "%-18s %-12s %12s %12s %12s\n", ...
        "TransitionType", ...
        "Learner", ...
        "MeanRT_Z", ...
        "SEM", ...
        "N");

    for i = 1:height(TblDesc)

        fprintf(fid, "%-18s %-12d %12.4f %12.4f %12d\n", ...
            string(TblDesc.TransitionType(i)), ...
            TblDesc.Learner(i), ...
            TblDesc.MeanRT_Z(i), ...
            TblDesc.SEM(i), ...
            TblDesc.N(i));

    end

    fprintf(fid, "\n");

    % ------------------------------------------------------------
    % Plot — transition types
    % ------------------------------------------------------------

    figName = fullfile(resultsDir, ...
        "16_TransitionType_" + cond + ".png");

    figure('Position',[300 300 850 450]);
    hold on;

    x = 1:numel(transitionOrder);
    barWidth = 0.34;

    learnerVals = NaN(numel(transitionOrder),1);
    nonLearnerVals = NaN(numel(transitionOrder),1);

    learnerSEM = NaN(numel(transitionOrder),1);
    nonLearnerSEM = NaN(numel(transitionOrder),1);

    for i = 1:numel(transitionOrder)

        idxL = ...
            string(TblDesc.TransitionType) == transitionOrder(i) & ...
            TblDesc.Learner == 1;

        idxNL = ...
            string(TblDesc.TransitionType) == transitionOrder(i) & ...
            TblDesc.Learner == 0;

        learnerVals(i) = TblDesc.MeanRT_Z(idxL);
        nonLearnerVals(i) = TblDesc.MeanRT_Z(idxNL);

        learnerSEM(i) = TblDesc.SEM(idxL);
        nonLearnerSEM(i) = TblDesc.SEM(idxNL);

    end

    thisColors = condColors(char(cond));

    learnerColor = thisColors(1,:);
    nonLearnerColor = thisColors(2,:);

    b1 = bar(x - barWidth/2, learnerVals, barWidth, ...
        'FaceColor', learnerColor, ...
        'EdgeColor', 'none');

    b2 = bar(x + barWidth/2, nonLearnerVals, barWidth, ...
        'FaceColor', nonLearnerColor, ...
        'EdgeColor', 'none');

    errorbar(x - barWidth/2, learnerVals, learnerSEM, ...
        'k.', ...
        'LineWidth',1.3);

    errorbar(x + barWidth/2, nonLearnerVals, nonLearnerSEM, ...
        'k.', ...
        'LineWidth',1.3);

    yline(0, '--k', ...
        'LineWidth',1.2, ...
        'Alpha',0.35);

    xticks(x);
    xticklabels(transitionOrder);
    xtickangle(25);

    ylabel('RT z-score');

    cleanCond = erase(cond, "ms");

    title("Transition sensitivity — " + cleanCond + " ms", ...
        'Interpreter','none');

    legend([b1 b2], ...
        {'Future learners','Future non-learners'}, ...
        'Location','northoutside', ...
        'Orientation','horizontal', ...
        'Box','off');

    grid on
    box off

    ax = gca;
    ax.FontSize = 12;
    ax.GridAlpha = 0.15;
    ax.LineWidth = 1;

    hold off;

    saveas(gcf, figName);
    close;

    % ------------------------------------------------------------
    % Repeat/switch descriptive statistics
    % ------------------------------------------------------------

    [G2, repeatGroup, learnerGroup2] = ...
        findgroups(string(Tc.RepeatSwitch), Tc.Learner);

    meanRTz2 = splitapply(@mean, Tc.RT_Z, G2);
    semRTz2 = splitapply(@(x) std(x,"omitnan") ./ sqrt(sum(~isnan(x))), Tc.RT_Z, G2);
    nRTz2 = splitapply(@(x) sum(~isnan(x)), Tc.RT_Z, G2);

    TblDesc2 = table(repeatGroup, learnerGroup2, meanRTz2, semRTz2, nRTz2, ...
        'VariableNames', ...
        {'RepeatSwitch','Learner','MeanRT_Z','SEM','N'});

    fprintf(fid, "REPEAT/SWITCH DESCRIPTIVE STATISTICS\n");
    fprintf(fid, "------------------------------------\n\n");

    fprintf(fid, "%-18s %-12s %12s %12s %12s\n", ...
        "RepeatSwitch", ...
        "Learner", ...
        "MeanRT_Z", ...
        "SEM", ...
        "N");

    for i = 1:height(TblDesc2)

        fprintf(fid, "%-18s %-12d %12.4f %12.4f %12d\n", ...
            string(TblDesc2.RepeatSwitch(i)), ...
            TblDesc2.Learner(i), ...
            TblDesc2.MeanRT_Z(i), ...
            TblDesc2.SEM(i), ...
            TblDesc2.N(i));

    end

    fprintf(fid, "\n\n");

    % ------------------------------------------------------------
    % Plot — repeat vs switch
    % ------------------------------------------------------------

    figName2 = fullfile(resultsDir, ...
        "16_RepeatSwitch_" + cond + ".png");

    figure('Position',[300 300 650 430]);
    hold on;

    x = 1:numel(repeatOrder);

    learnerVals = NaN(numel(repeatOrder),1);
    nonLearnerVals = NaN(numel(repeatOrder),1);

    learnerSEM = NaN(numel(repeatOrder),1);
    nonLearnerSEM = NaN(numel(repeatOrder),1);

    for i = 1:numel(repeatOrder)

        idxL = ...
            string(TblDesc2.RepeatSwitch) == repeatOrder(i) & ...
            TblDesc2.Learner == 1;

        idxNL = ...
            string(TblDesc2.RepeatSwitch) == repeatOrder(i) & ...
            TblDesc2.Learner == 0;

        learnerVals(i) = TblDesc2.MeanRT_Z(idxL);
        nonLearnerVals(i) = TblDesc2.MeanRT_Z(idxNL);

        learnerSEM(i) = TblDesc2.SEM(idxL);
        nonLearnerSEM(i) = TblDesc2.SEM(idxNL);

    end

    b1 = bar(x - barWidth/2, learnerVals, barWidth, ...
        'FaceColor', learnerColor, ...
        'EdgeColor', 'none');

    b2 = bar(x + barWidth/2, nonLearnerVals, barWidth, ...
        'FaceColor', nonLearnerColor, ...
        'EdgeColor', 'none');

    errorbar(x - barWidth/2, learnerVals, learnerSEM, ...
        'k.', ...
        'LineWidth',1.3);

    errorbar(x + barWidth/2, nonLearnerVals, nonLearnerSEM, ...
        'k.', ...
        'LineWidth',1.3);

    yline(0, '--k', ...
        'LineWidth',1.2, ...
        'Alpha',0.35);

    xticks(x);
    xticklabels(repeatOrder);

    ylabel('RT z-score');

    title("Repeat vs switch — " + cleanCond + " ms", ...
        'Interpreter','none');

    legend([b1 b2], ...
        {'Future learners','Future non-learners'}, ...
        'Location','northoutside', ...
        'Orientation','horizontal', ...
        'Box','off');

    grid on
    box off

    ax = gca;
    ax.FontSize = 12;
    ax.GridAlpha = 0.15;
    ax.LineWidth = 1;

    hold off;

    saveas(gcf, figName2);
    close;

end

fclose(fid);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SMART Excel Analyzer - Part 17
% 1) Load transition-ready SMART table from Part 15.1
% 2) Compute participant-level repeat/switch cost:
%    - Repeat mean RT_Z
%    - Switch mean RT_Z
%    - SwitchCost_Z = Switch mean RT_Z - Repeat mean RT_Z
% 3) Test whether repeat/switch cost predicts learning:
%    - Learner ~ SMART_length + SwitchCost_Z
%    - GenMean ~ SMART_length + SwitchCost_Z
% 4) Test whether repeat/switch cost differs across learners:
%    - SwitchCost_Z ~ Learner + SMART_length
% 5) Save txt output and plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
clc;

baseDir = "D:\Data\SMART";
dataDir = fullfile(baseDir, "data");
resultsDir = fullfile(baseDir, "results");

transitionFile = fullfile(dataDir, "SMART_Category_Transitions_preprocessed.xlsx");

txtOut = fullfile(resultsDir, "17_SMART_repeat_switch_cost_results.txt");
figOut1 = fullfile(resultsDir, "17_SMART_repeat_switch_cost_by_learner.png");
figOut2 = fullfile(resultsDir, "17_SMART_switch_cost_predicts_genmean.png");

if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end

% Step 1 — Load transition-ready table

T = readtable(transitionFile, "VariableNamingRule","preserve", "TextType","string");

conditions = ["ms0","ms250","ms500","ms1100"];

T.RT_Z = str2double(string(T.RT_Z));
T.GenMean = str2double(string(T.GenMean));
T.Learner = str2double(string(T.Learner));

T = T(~isnan(T.RT_Z), :);

% Step 2 — Compute participant-level repeat/switch cost

participants = unique(string(T.Participant));

participantList = strings(0,1);
conditionList = strings(0,1);
learnerList = [];
genMeanList = [];
repeatMeanList = [];
switchMeanList = [];
switchCostList = [];
nRepeatList = [];
nSwitchList = [];

for i = 1:numel(participants)

    pid = participants(i);
    idxP = string(T.Participant) == pid;

    valsRepeat = T.RT_Z(idxP & string(T.RepeatSwitch) == "repeat");
    valsSwitch = T.RT_Z(idxP & string(T.RepeatSwitch) == "switch");

    if isempty(valsRepeat) || isempty(valsSwitch)
        continue
    end

    repeatMean = mean(valsRepeat, "omitnan");
    switchMean = mean(valsSwitch, "omitnan");
    switchCost = switchMean - repeatMean;

    participantList(end+1,1) = pid;
    conditionList(end+1,1) = string(T.SMART_length(find(idxP,1)));
    learnerList(end+1,1) = T.Learner(find(idxP,1));
    genMeanList(end+1,1) = T.GenMean(find(idxP,1));

    repeatMeanList(end+1,1) = repeatMean;
    switchMeanList(end+1,1) = switchMean;
    switchCostList(end+1,1) = switchCost;

    nRepeatList(end+1,1) = sum(~isnan(valsRepeat));
    nSwitchList(end+1,1) = sum(~isnan(valsSwitch));

end

TblCost = table(participantList, conditionList, learnerList, genMeanList, ...
    repeatMeanList, switchMeanList, switchCostList, nRepeatList, nSwitchList, ...
    'VariableNames', {'Participant','SMART_length','Learner','GenMean', ...
    'RepeatMean_Z','SwitchMean_Z','SwitchCost_Z','NRepeat','NSwitch'});

TblCost.SMART_length = categorical(TblCost.SMART_length, conditions);
TblCost.Learner = categorical(TblCost.Learner);

% Step 3 — Fit models

mdl_cost_group = fitlm(TblCost, ...
    'SwitchCost_Z ~ Learner + SMART_length');

mdl_learner = fitglm(TblCost, ...
    'Learner ~ SMART_length + SwitchCost_Z', ...
    'Distribution','binomial');

mdl_gen = fitlm(TblCost, ...
    'GenMean ~ SMART_length + SwitchCost_Z');

% Step 4 — Save txt output

fid = fopen(txtOut, 'w');

if fid == -1
    error("Could not open txt output file: %s", txtOut);
end

fprintf(fid, "REPEAT/SWITCH COST RESULTS\n");
fprintf(fid, "==========================\n\n");

fprintf(fid, "Input file: %s\n\n", transitionFile);
fprintf(fid, "SwitchCost_Z = mean RT_Z switch trials - mean RT_Z repeat trials\n");
fprintf(fid, "RT_Z was computed within participant and block in Part 15.1\n\n");

fprintf(fid, "PARTICIPANT-LEVEL SUMMARY\n");
fprintf(fid, "=========================\n\n");
fprintf(fid, "Participants included: %d\n", height(TblCost));
fprintf(fid, "Learners: %d\n", sum(TblCost.Learner == categorical(1)));
fprintf(fid, "Non-learners: %d\n\n", sum(TblCost.Learner == categorical(0)));

fprintf(fid, "MODEL 1 - SWITCH COST BY LEARNER STATUS\n");
fprintf(fid, "=======================================\n\n");
fprintf(fid, "SwitchCost_Z ~ Learner + SMART_length\n\n");

coefTable = mdl_cost_group.Coefficients;

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)
    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Properties.RowNames{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));
end

fprintf(fid, "\nMODEL 2 - LEARNER PROBABILITY\n");
fprintf(fid, "=============================\n\n");
fprintf(fid, "Learner ~ SMART_length + SwitchCost_Z\n\n");

coefTable = mdl_learner.Coefficients;

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)
    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Properties.RowNames{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));
end

fprintf(fid, "\nMODEL 3 - GENERALIZATION STRENGTH\n");
fprintf(fid, "=================================\n\n");
fprintf(fid, "GenMean ~ SMART_length + SwitchCost_Z\n\n");

coefTable = mdl_gen.Coefficients;

fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
    "Term", "Estimate", "SE", "tStat", "pValue");

for i = 1:height(coefTable)
    fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
        string(coefTable.Properties.RowNames{i}), ...
        coefTable.Estimate(i), ...
        coefTable.SE(i), ...
        coefTable.tStat(i), ...
        coefTable.pValue(i));
end

fprintf(fid, "\nDESCRIPTIVE STATISTICS\n");
fprintf(fid, "======================\n\n");

valsL = TblCost.SwitchCost_Z(TblCost.Learner == categorical(1));
valsNL = TblCost.SwitchCost_Z(TblCost.Learner == categorical(0));

fprintf(fid, "Future learners:     mean = %.4f | SD = %.4f | n = %d\n", ...
    mean(valsL,"omitnan"), std(valsL,"omitnan"), sum(~isnan(valsL)));

fprintf(fid, "Future non-learners: mean = %.4f | SD = %.4f | n = %d\n", ...
    mean(valsNL,"omitnan"), std(valsNL,"omitnan"), sum(~isnan(valsNL)));

fclose(fid);

% Step 5 — Plot switch cost by learner status

figure('Position',[300 300 620 450]);
hold on;

rng(1);

valsL = TblCost.SwitchCost_Z(TblCost.Learner == categorical(1));
valsNL = TblCost.SwitchCost_Z(TblCost.Learner == categorical(0));

xL = ones(size(valsL)) + (rand(size(valsL)) - 0.5) * 0.18;
xNL = 2 * ones(size(valsNL)) + (rand(size(valsNL)) - 0.5) * 0.18;

scatter(xL, valsL, 45, ...
    'filled', ...
    'MarkerFaceColor', [0.20 0.20 0.20], ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', 'none');

scatter(xNL, valsNL, 45, ...
    'filled', ...
    'MarkerFaceColor', [0.65 0.65 0.65], ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', 'none');

errorbar(1, mean(valsL,"omitnan"), std(valsL,"omitnan")/sqrt(sum(~isnan(valsL))), ...
    'kd', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'LineWidth', 1.8);

errorbar(2, mean(valsNL,"omitnan"), std(valsNL,"omitnan")/sqrt(sum(~isnan(valsNL))), ...
    'kd', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'LineWidth', 1.8);

yline(0, '--k', 'LineWidth', 1.2, 'Alpha', 0.35);

xlim([0.5 2.5]);
xticks([1 2]);
xticklabels({'Future learners','Future non-learners'});

ylabel('Switch cost in RT_Z');
title('Participant-level repeat/switch cost', 'Interpreter','none');

grid on
box off
ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut1);
close;

% Step 6 — Plot switch cost vs GenMean

figure('Position',[300 300 620 450]);
hold on;

scatter(TblCost.SwitchCost_Z, TblCost.GenMean, 45, ...
    'filled', ...
    'MarkerFaceColor', [0.35 0.35 0.35], ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', 'none');

mdl_simple = fitlm(TblCost, 'GenMean ~ SwitchCost_Z');

xGrid = linspace(min(TblCost.SwitchCost_Z), max(TblCost.SwitchCost_Z), 100)';
yPred = predict(mdl_simple, table(xGrid, 'VariableNames', {'SwitchCost_Z'}));

plot(xGrid, yPred, 'k-', 'LineWidth', 2.2);

xlabel('Switch cost in RT_Z');
ylabel('GenMean (%)');

title('Repeat/switch cost and generalization', 'Interpreter','none');

grid on
box off
ax = gca;
ax.FontSize = 12;
ax.GridAlpha = 0.15;
ax.LineWidth = 1;

hold off;

saveas(gcf, figOut2);
close;


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

function printCoefTable(fid, coefTbl)

    fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
        "Term", "Beta", "SE", "tStat", "pValue");

    fprintf(fid, "%-30s %12s %12s %12s %12s\n", ...
        "----", "----", "--", "-----", "------");

    for i = 1:height(coefTbl)

        termName = string(coefTbl.Properties.RowNames{i});

        fprintf(fid, "%-30s %12.4f %12.4f %12.4f %12.6f\n", ...
            termName, ...
            coefTbl.Estimate(i), ...
            coefTbl.SE(i), ...
            coefTbl.tStat(i), ...
            coefTbl.pValue(i));

    end

end