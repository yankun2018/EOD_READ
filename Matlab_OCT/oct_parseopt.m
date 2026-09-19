function opt = oct_parseopt(opt, args)
%OCT_PARSEOPT  把 {'Name', value, ...} 合并进默认选项结构体（大小写不敏感）。

if numel(args) == 1 && isstruct(args{1})
    args = reshape([fieldnames(args{1}).'; struct2cell(args{1}).'], 1, []);
end
if mod(numel(args), 2) ~= 0
    error('oct_parseopt:args', '选项必须成对出现');
end
f = fieldnames(opt);
for k = 1:2:numel(args)
    if ~(ischar(args{k}) || isstring(args{k}))
        error('oct_parseopt:name', '第 %d 个选项名不是字符串', (k+1)/2);
    end
    idx = find(strcmpi(char(args{k}), f), 1);
    if isempty(idx)
        error('oct_parseopt:badOpt', '未知选项 ''%s''，可用的有: %s', ...
              char(args{k}), strjoin(f.', ', '));
    end
    opt.(f{idx}) = args{k+1};
end
end
