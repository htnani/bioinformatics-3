%%
gseData = getgeodata('GSE5847', 'ToFile', 'GSE5847.txt');
sampleGrp = gseData.Header.Samples.characteristics_ch1(1,:);
sampleGrp;

%%
%gplData = getgeodata('GPL96', 'ToFile', 'GPL96.txt');
gplData = geosoftread('GPL96.txt');
gplProbesetIDs = gplData.Data(:, strcmp(gplData.ColumnNames, 'ID'));
geneSymbols = gplData.Data(:, strcmp(gplData.ColumnNames, 'Gene Symbol'));
gseData.Data = rownames(gseData.Data, ':', geneSymbols);
gseData.Data(1:5,1:5);
sampleSources = unique(gseData.Header.Samples.source_name_ch1);

%%
stromaIdx = strcmpi(sampleSources{1}, gseData.Header.Samples.source_name_ch1);
nStroma = sum(stromaIdx);
stromaData = gseData.Data(:, stromaIdx);
stromaGrp = sampleGrp(stromaIdx);
nStromaIBC = sum(strcmp('IBC', stromaGrp));
nStromaNonIBC = sum(strcmp('non-IBC', stromaGrp));
stromaData = colnames(stromaData, ':', stromaGrp);

fID = 331:339;
zValues = zscore(stromaData.(':')(':'), 0, 2);
bw = 0.25;
edges = -10:bw:10;
bins = edges(1:end-1) + diff(edges)/2;
histStroma = histc(zValues(fID, :)', edges) ./ (stromaData.NCols*bw);
figure;
for i = 1:length(fID)
    subplot(3,3,i);
    bar(edges, histStroma(:,i), 'histc')
    xlim([-3 3])
    if i <= length(fID)-3
        set(gca, 'XtickLabel', [])
    end
    title(sprintf('gene%d - %s', fID(i), stromaData.RowNames{fID(i)}))
end
suptitle('Gene Expression Value Distributions');

% Histogram of the normalized gene expression
% Histogram with some sample genes

[mask, stromaData] = genevarfilter(stromaData);
randn('state', 0)
[pvalues, tscores]=mattest(stromaData(:, 'IBC'), stromaData(:, 'non-IBC'),'Showhist', true', 'showplot', true, 'permute', 1000);

sum(pvalues < 0.001)
testResults1 = [pvalues, tscores];
testResults1 = sortrows(testResults1);
testResults1(1:20, :)

pvaluesCorr = mattest(stromaData(:, 'IBC'), stromaData(:, 'non-IBC'), 'Permute', 10000);

% Further a t statistic test is applied on each gene% to find significantly
% different expressed genes

cutoff = 0.05;
sum(pvaluesCorr < cutoff)

figure;
[pFDR, qvalues] = mafdr(pvaluesCorr, 'showplot', true);

% Execution of a false discovery rate test for testing on false positives
% Many genes with low FDR implies that the two groups, IBC and non-IBC, are
% different

sum(qvalues < cutoff)

pvaluesBH = mafdr(pvaluesCorr, 'BHFDR', true);
sum(pvaluesBH < cutoff)

testResults2 = [tscores pvaluesCorr pFDR qvalues pvaluesBH];
testResults2 = colnames(testResults2, 5, {'FDR_BH'});
testResults2 = sortrows(testResults2, 2);
testResults2(1:23, :)


diffStruct = mavolcanoplot(stromaData(:, 'IBC'), stromaData(:, 'non-IBC'), pvaluesCorr);

% A gene is differentially reported between the groups IBC and non-IBC
% if it has statistical and biological significance.
% The volcano plot shows the ?log10 ratio of p-values against
% the biological effect and you can see the differently expressed genes.

%%
nDiffGenes = diffStruct.PValues.NRows;
down_geneidx = find(diffStruct.FoldChanges < 0);
down_genes = rownames(diffStruct.FoldChanges, down_geneidx);
start_nDownGenes = length(down_geneidx);
nUpGenes = sum(diffStruct.FoldChanges > 0);

% Due to the fact that I dont have upregulated genes, I perform Gene Ontology
% on the downregulated genes.

%%
huGenes = rownames(stromaData);
for i = 1:start_nDownGenes
    if isempty(down_genes{i})
        nDownGenes = start_nDownGenes-1;
    else
    down_geneidx(i) = find(strncmpi(huGenes, down_genes{i}, length(down_genes{i})), 1);
                      % find the match find( , 1)
    end
end


%% Gene Ontology is used to annotate the differentially expressed genes

GO = geneont('live',true);
HGann = goannotread('gene_association.goa_human','Aspect','F','Fields',{'DB_Object_Symbol','GOid'});

HGmap = containers.Map();
for i=1:numel(HGann)
    key = HGann(i).DB_Object_Symbol;
    if isKey(HGmap,key)
        HGmap(key) = [HGmap(key) HGann(i).GOid];
    else
        HGmap(key) = HGann(i).GOid;
    end
end

%%
% m is like 2 million
m = GO.Terms(end).id;
chipgenesCount = zeros(m,1);
downgenesCount  = zeros(m,1);
for i = 1:length(huGenes)
    if isKey(HGmap,huGenes{i})
        goid = getrelatives(GO,HGmap(huGenes{i}));
        chipgenesCount(goid) = chipgenesCount(goid) + 1;
        if (any(i == down_geneidx))
            downgenesCount(goid) = downgenesCount(goid) +1;
        end
    end
end

%% Calculating statistical significance of the GO terms

gopvalues = hygepdf(downgenesCount,max(chipgenesCount),max(downgenesCount),chipgenesCount);
[dummy, idx] = sort(gopvalues);

report = sprintf('GO Term     p-value     counts      definition\n');
for i = 1:10
    term = idx(i);
    report = sprintf('%s%s\t%-1.5f\t%3d / %3d\t%s...\n',report, char(num2goid(term)), gopvalues(term), downgenesCount(term), chipgenesCount(term),GO(term).Term.definition(2:min(50,end)));
end
disp(report);

%% visualize ontology
fcnAncestors = GO(getancestors(GO,idx(1:5)));
[cm acc rels] = getmatrix(fcnAncestors);
BG = biograph(cm,get(fcnAncestors.Terms,'name'));

for i=1:numel(acc)
    pval = gopvalues(acc(i));
    color = [(1-pval).^(1) pval.^(1/8) pval.^(1/8)];
    set(BG.Nodes(i),'Color',color);
end
view(BG)
