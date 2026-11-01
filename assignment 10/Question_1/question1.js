const results = document.querySelector("#results");
let balance = 10000;

function displayResult(message) {
    const result = document.createElement("p");
    result.textContent = message;
    results.append(result);
}

function calculate(num1, num2, callback) {
    callback(num1, num2);
}

function calculateBill(price1, price2, price3, callback) {
    const total = price1 + price2 + price3;
    callback(total);
}

function withdrawMoney(amount, callback) {
    setTimeout(() => {
        balance -= amount;
        callback(balance);
    }, 2000);
}

calculate(10, 20, (num1, num2) => {
    displayResult(`The sum is: ${num1 + num2}`);
});

calculateBill(200, 300, 500, (total) => {
    displayResult(`The total bill is: ${total}`);
});

withdrawMoney(5000, (remainingBalance) => {
    displayResult(`The remaining balance is: ${remainingBalance}`);
});
