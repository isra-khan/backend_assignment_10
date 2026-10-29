// Question 2 - Student Profile from an API
// A school website receives the following student profile from an API. Prepare the values required for a profile summary
// without repeatedly accessing each property.
// Sample profile: { name: "Sara Ahmed", age: 19, department: "Software Engineering", address: { city: "Karachi",
// country: "Pakistan" } }
// - Extract the student's name and age into variables.
// - Store the department in a local variable named program, while keeping the original property name unchanged in the
// object.
// - Extract the city and country from the address information.
// - The API may sometimes omit the student phone number. Prepare a phone variable that uses "Not provided" when
// no phone value is available.
// - Display a short profile summary containing the student's name, program, city, and phone value.

const sampleProfile={ name: "Sara Ahmed", age: 19, department: "Software Engineering", address: { city: "Karachi",
 country: "Pakistan" } }
 const {name:studentName,age:age,deparment:program,address:{city,country},phone='Not Provided'}=sampleProfile;
console.log(`Name: ${studentName}, Program: ${program}, City: ${city}, Phone: ${phone}`);