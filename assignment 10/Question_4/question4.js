function registerStudent(studentName, seatAvailable) {
    return new Promise((resolve, reject) => {
        if (seatAvailable) {
            resolve(`Registration confirmed for ${studentName}.`);
        } else {
            reject(new Error(`Registration failed for ${studentName}: the class is full.`));
        }
    });
}

registerStudent("Alex", true)
    .then((message) => {
        console.log(message);
    })
    .catch((error) => {
        console.log(error.message);
    });

registerStudent("Jordan", false)
    .then((message) => {
        console.log(message);
    })
    .catch((error) => {
        console.log(error.message);
    });
