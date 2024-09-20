function mybars(Y,E,color)

% if color is not defined;
if ~exist('color','var')
    for i=1:length(Y)
    color(i,:) = repmat(i./length(Y),1,3);
    end
end

n=length(Y);
if min(size(E))==1
for i=1:n
    y=zeros(n,1);
    %e=zeros(n,1);
    y(i)=Y(i);
    %e(i)=E(i);
    bar(y,'FaceColor',color(i,:));
    hold on
    line([i;i],[y(i)-E(i);y(i)+E(i)],'color','k','linewidth',3)
    %errorbar(i,X(i),E(i))
    hold on
end
elseif min(size(E))==2 % Upper and lower bounds
    for i=1:n
    y=zeros(n,1);
    %e=zeros(n,1);
    y(i)=Y(i);
    %e(i)=E(i);
    bar(y,'FaceColor',color(i,:));
    hold on
    line([i;i],[y(i)-E(1,i);y(i)+E(2,i)],'color','k','linewidth',3)
    %errorbar(i,X(i),E(i))
    hold on
end
end