



n=int(input("Please Enter your number : "))
nums=range(1,n+1,1)
even=0
odd=0
for i in nums:
    if i % 2 == 0:
        even = even + i
       
    else:
        odd = odd + i
print(f"Sum of even numbers from 1 to {n} is {even}")       
print(f"Sum of odd numbers from 1 to {n} is {odd}")




