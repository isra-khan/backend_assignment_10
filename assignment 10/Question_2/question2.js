function prepareFood(callback) {
    console.log("Preparing food: started");
    setTimeout(() => {
        console.log("Preparing food: finished");
        callback();
    }, 1000);
}

function packFood(callback) {
    console.log("Packing food: started");
    setTimeout(() => {
        console.log("Packing food: finished");
        callback();
    }, 1000);
}

function notifyCustomer(callback) {
    console.log("Notifying customer: started");
    setTimeout(() => {
        console.log("Notifying customer: finished");
        callback();
    }, 1000);
}

function runWithNestedCallbacks(onComplete) {
    console.log("Nested callback version:");
    prepareFood(() => {
        packFood(() => {
            notifyCustomer(onComplete);
        });
    });
}

function prepareFoodPromise() {
    console.log("Preparing food: started");
    return new Promise((resolve) => {
        setTimeout(() => {
            console.log("Preparing food: finished");
            resolve();
        }, 1000);
    });
}

function packFoodPromise() {
    console.log("Packing food: started");
    return new Promise((resolve) => {
        setTimeout(() => {
            console.log("Packing food: finished");
            resolve();
        }, 1000);
    });
}

function notifyCustomerPromise() {
    console.log("Notifying customer: started");
    return new Promise((resolve) => {
        setTimeout(() => {
            console.log("Notifying customer: finished");
            resolve();
        }, 1000);
    });
}

async function runWithAsyncAwait() {
    console.log("Promise/async-await version:");
    await prepareFoodPromise();
    await packFoodPromise();
    await notifyCustomerPromise();
}


runWithNestedCallbacks(() => {
    runWithAsyncAwait();
});
