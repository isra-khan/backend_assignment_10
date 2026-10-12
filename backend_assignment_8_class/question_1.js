
// Store all order amounts in an array
const orders = [1200, 450, 3000, 750, 1500, 250, 4200, 900];

// Display the original array
console.log("Original Array:", orders);

// Find the first order amount greater than 2000
const result = orders.find(amount => amount > 2000);
console.log("First order greater than 2000:", result);

// Create a list of orders greater than 1000
const seperateList = orders.filter(amount => amount > 1000);
console.log("Orders greater than 1000:", seperateList);

// Calculate the total of all order amounts
const total = orders.reduce((sum, amount) => {
    return sum + amount;
}, 0);
console.log("Total of all orders:", total);
