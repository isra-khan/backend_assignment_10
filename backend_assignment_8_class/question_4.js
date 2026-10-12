
const inventory = new Map([
    ['apples', 500],
    ['bananas', 300],
    ['oranges', 200]
]);

// 1. Display the original inventory
console.log("Original inventory:", inventory);

// 2. Add a new product
inventory.set('grapes', 500);
console.log("After adding grapes:", inventory);

// 3. Update an existing product quantity
inventory.set('apples', 600);
console.log("Updated apples quantity:", inventory.get('apples'));

// 4. Retrieve a specific product quantity
console.log("Bananas quantity:", inventory.get('bananas'));

// 5. Check whether a product exists
console.log("Does oranges exist?", inventory.has('oranges'));

// 6. Remove one product
inventory.delete('bananas');
console.log("After removing bananas:", inventory);

// 7. Display the number of product entries
console.log("Number of products:", inventory.size);

// 8. Display all product names
console.log("Product names:", [...inventory.keys()]);

// 9. Display all quantities
console.log("Product quantities:", [...inventory.values()]);

// 10. Print each product and quantity using Map iteration
inventory.forEach((quantity, product) => {
    console.log(`${product}: ${quantity}`);
});

// 11. Empty the inventory
inventory.clear();

// 12. Display the final size
console.log("Final inventory size:", inventory.size);
