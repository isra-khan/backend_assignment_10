


a=[0,1,2,3,4,5,6,7,8,9]

ran=range(0,len(a),1)
for i in ran:
    print(a[i])


    for i in a:
        print(i)
       # print(help(list)   )

b=[1,2,3,4]
mean=0
for i in range(0,len(b),1):
  mean+=b[i]
mean=mean/len(b)
print(f"means is {mean}")


# new elements in list
a=[30,2,4,6,9,40,20,10,0]
greatest=0

for i in range(0,len(a),1):
   if(a[i]>greatest):
      greatest=a[i]
      index=i


print(f"greatest number is {greatest} and index is {index }")

