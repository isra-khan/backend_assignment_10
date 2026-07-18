


name="Isra khan"
nam=""
for i in range(len(name)-1,-1,-1):
    nam=nam+name[i]
print(nam)




palindrome=input("Please Enter your word :")
rev=""
for i in range(len(palindrome)-1,-1,-1):
   rev=rev+palindrome[i]
if(rev==palindrome):
       print(f"{palindrome} is a palindrome")
else:
       print(f"{palindrome} is not a palindrome")    